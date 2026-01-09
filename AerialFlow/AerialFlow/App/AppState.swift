import Combine
import Foundation
import AppKit
import os
import UserNotifications

@MainActor
final class AppState: ObservableObject {
    private let logger = Logger(subsystem: Constants.loggerSubsystem, category: "AppState")

    private let userDefaults: UserDefaults
    private let fileSystem: any FileSystem
    private let directoryDetector: ActiveVideoDirectoryDetector
    private let catalog: any AerialCataloging
    private let catalogPresentation: CatalogPresentationService
    private let stateStore: any AerialEngineStateStore
    private let excludedAerialsCleanupStateStore: any ExcludedAerialsCleanupStateStoring
    private let powerEventObserver: any PowerEventObserving
    private let screensaverLauncher: any ScreensaverLaunching
    private let hotkeyBinder: any HotkeyBinding
    private let launchAtLoginCoordinator: LaunchAtLoginCoordinator
    private let excludedAerialsCleaner: ExcludedAerialsCleaner
    private let engine: AerialEngine
    private let brightnessStore: any AerialBrightnessStoring
    let updaterViewModel: UpdaterViewModel
    private let systemAccessProbe: any SystemAccessProbing
    private let notificationPermissionService: any NotificationPermissionServicing
    private let systemSettingsOpener: any SystemSettingsOpening

    private let ui: AppUIState
    private let settingsStore: AppSettingsStore
    private var changeForwardingCancellables: Set<AnyCancellable> = []

    private lazy var rotationCoordinator: RotationCoordinator = {
        RotationCoordinator(
            stateStore: stateStore,
            engine: engine,
            initialSettings: settingsStore.settings,
            onDue: { [weak self] in
                guard let state = self else { return }
                await state.scheduledNextAerial()
            }
        )
    }()

    private lazy var excludedAerialsCleanupCoordinator: ExcludedAerialsCleanupCoordinator = {
        ExcludedAerialsCleanupCoordinator(
            stateStore: excludedAerialsCleanupStateStore,
            cleaner: excludedAerialsCleaner,
            initialSettings: settingsStore.settings,
            settingsProvider: { [weak self] in
                let state = self
                return await MainActor.run {
                    // If the owner is gone, treat as disabled/no-op.
                    state?.settingsStore.settings ?? AppSettings()
                }
            }
        )
    }()

    private lazy var powerEventCoordinator: PowerEventCoordinator = {
        PowerEventCoordinator(observer: powerEventObserver)
    }()

    private lazy var brightnessPrecomputeCoordinator: BrightnessPrecomputeCoordinator = {
        BrightnessPrecomputeCoordinator(catalog: catalog, store: brightnessStore)
    }()

    private lazy var notificationCoordinator: NotificationCoordinator = {
        NotificationCoordinator(service: notificationPermissionService)
    }()

    private lazy var systemAccessCoordinator: SystemAccessCoordinator = {
        SystemAccessCoordinator(probe: systemAccessProbe)
    }()

    private lazy var hotkeyCoordinator: HotkeyCoordinator = {
        HotkeyCoordinator(binder: hotkeyBinder)
    }()

    private lazy var diagnosticsSnapshotLoader: DiagnosticsSnapshotLoader = {
        DiagnosticsSnapshotLoader(
            fileSystem: fileSystem,
            directoryDetector: directoryDetector,
            stateStore: stateStore,
            nextScheduledChangeDate: { [weak self] in
                guard let self else { return nil }
                return await self.rotationCoordinator.nextScheduledChangeDate()
            }
        )
    }()

    var settings: AppSettings {
        get { settingsStore.settings }
        set { settingsStore.settings = newValue }
    }

    enum SettingsDestination: Hashable, Sendable, CaseIterable {
        case general
        case rotation
        case filtering
        case exclusions
        case hotkeys
        case diagnostics
        case advanced
        case about

        var title: String {
            switch self {
            case .general: return "General"
            case .rotation: return "Rotation"
            case .filtering: return "Filtering"
            case .exclusions: return "Exclusions"
            case .hotkeys: return "Hotkeys"
            case .diagnostics: return "Diagnostics"
            case .advanced: return "Advanced"
            case .about: return "About"
            }
        }

        var systemImage: String {
            switch self {
            case .general: return "gearshape"
            case .rotation: return "arrow.triangle.2.circlepath"
            case .filtering: return "sun.max"
            case .exclusions: return "minus.circle"
            case .hotkeys: return "keyboard"
            case .diagnostics: return "stethoscope"
            case .advanced: return "slider.horizontal.3"
            case .about: return "info.circle"
            }
        }

        var sidebarSectionTitle: String {
            switch self {
            case .general, .rotation, .filtering, .exclusions, .hotkeys:
                return "Settings"
            case .diagnostics:
                return "Tools"
            case .advanced, .about:
                return "Other"
            }
        }
    }

    var selectedSettingsDestination: SettingsDestination {
        get { ui.selectedSettingsDestination }
        set { ui.selectedSettingsDestination = newValue }
    }

    var isBusy: Bool { ui.isBusy }
    var statusLine: String { ui.statusLine }
    var lastErrorMessage: String? { ui.lastErrorMessage }
    var launchAtLoginErrorMessage: String? { ui.launchAtLoginErrorMessage }
    var isCleaningExcludedAerials: Bool { ui.isCleaningExcludedAerials }
    var systemAccessReport: SystemAccessReport? { ui.systemAccessReport }
    var notificationAuthorizationStatus: UNAuthorizationStatus? { ui.notificationAuthorizationStatus }
    var onboardingRequested: Bool { ui.onboardingRequested }

    private let onboardingUserDefaultsKey = "AerialFlow.didShowOnboarding"

    init(dependencies: AppDependencies, userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let settingsSnapshot = AppSettings.load(from: userDefaults)
        self.ui = AppUIState()
        self.settingsStore = AppSettingsStore(userDefaults: userDefaults, initialSettings: settingsSnapshot)

        self.fileSystem = dependencies.fileSystem
        self.directoryDetector = dependencies.directoryDetector
        self.catalog = dependencies.catalog
        self.catalogPresentation = dependencies.catalogPresentation
        self.stateStore = dependencies.stateStore
        self.excludedAerialsCleanupStateStore = dependencies.excludedAerialsCleanupStateStore
        self.powerEventObserver = dependencies.powerEventObserver
        self.screensaverLauncher = dependencies.screensaverLauncher
        self.hotkeyBinder = dependencies.hotkeyBinder
        self.launchAtLoginCoordinator = dependencies.launchAtLoginCoordinator
        self.excludedAerialsCleaner = dependencies.excludedAerialsCleaner
        self.engine = dependencies.engine
        self.brightnessStore = dependencies.brightnessStore
        self.updaterViewModel = dependencies.updaterViewModel
        self.systemAccessProbe = dependencies.systemAccessProbe
        self.notificationPermissionService = dependencies.notificationPermissionService
        self.systemSettingsOpener = dependencies.systemSettingsOpener

        // Forward change notifications from owned state objects to keep `@EnvironmentObject AppState` stable.
        ui.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &changeForwardingCancellables)
        settingsStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &changeForwardingCancellables)

        settingsStore.onSettingsChanged = { [weak self] newSettings in
            guard let self else { return }
            Task { await self.rotationCoordinator.updateSettings(newSettings) }
            Task { await self.excludedAerialsCleanupCoordinator.updateSettings(newSettings) }
            self.refreshSystemAccessReport()
        }

        reconcileLaunchAtLoginSetting()
        bindHotkeys()
        Task { await rotationCoordinator.start() }
        Task { await excludedAerialsCleanupCoordinator.updateSettings(settingsSnapshot) }
        Task { await excludedAerialsCleanupCoordinator.startIfEnabled() }
        startPowerEventObservation()
        brightnessPrecomputeCoordinator.start()
        refreshSystemAccessReport()
        if NSClassFromString("XCTestCase") == nil {
            Task { await refreshNotificationAuthorizationStatus() }
        }

        if !userDefaults.bool(forKey: onboardingUserDefaultsKey) {
            userDefaults.set(true, forKey: onboardingUserDefaultsKey)
            ui.onboardingRequested = true
        }
        
        // Update status line with current asset name if available.
        // Avoid overwriting any user-initiated status updates that may occur shortly after init.
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.ui.statusLine == "Ready", self.ui.lastErrorMessage == nil else { return }
            guard let lastAssetID = await stateStore.getLastAssetID(), !lastAssetID.isEmpty else { return }
            guard let displayName = await catalogPresentation.assetDisplayName(for: lastAssetID) else { return }
            guard self.ui.statusLine == "Ready", self.ui.lastErrorMessage == nil else { return }
            self.ui.statusLine = displayName
        }
    }

    func refreshSystemAccessReport() {
        let settingsSnapshot = settingsStore.settings
        Task.detached { [weak self, systemAccessCoordinator] in
            let report = systemAccessCoordinator.probe(settings: settingsSnapshot)
            await MainActor.run { [weak self, report] in
                self?.ui.systemAccessReport = report
                if report.items.contains(where: { $0.state != .ok }) {
                    self?.ui.onboardingRequested = true
                }
            }
        }
    }

    func consumeOnboardingRequest() -> Bool {
        if ui.onboardingRequested {
            ui.onboardingRequested = false
            return true
        }
        return false
    }

    func refreshNotificationAuthorizationStatus() async {
        let status = await notificationCoordinator.authorizationStatus()
        ui.notificationAuthorizationStatus = status
    }

    func requestNotificationAuthorization() {
        Task { [weak self] in
            _ = await self?.notificationCoordinator.requestAuthorization()
            await self?.refreshNotificationAuthorizationStatus()
        }
    }

    private lazy var actions: AppUserActions = {
        AppUserActions(
            ui: ui,
            settingsStore: settingsStore,
            stateStore: stateStore,
            rotationCoordinator: rotationCoordinator,
            excludedAerialsCleanupCoordinator: excludedAerialsCleanupCoordinator,
            catalogPresentation: catalogPresentation,
            screensaverLauncher: screensaverLauncher,
            systemSettingsOpener: systemSettingsOpener,
            notificationCoordinator: notificationCoordinator
        )
    }()

    var isRotationEnabled: Bool { actions.isRotationEnabled }
    var isPaused: Bool { actions.isPaused }

    func setRotationEnabled(_ enabled: Bool) {
        actions.setRotationEnabled(enabled)
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        let previous = settingsStore.settings.launchAtLogin
        guard previous != enabled else { return }

        ui.launchAtLoginErrorMessage = nil
        let update = launchAtLoginCoordinator.setLaunchAtLoginEnabled(
            enabled,
            previousSettingValue: previous
        )
        settingsStore.settings.launchAtLogin = update.launchAtLoginEnabled
        ui.launchAtLoginErrorMessage = update.errorMessage
    }

    func nextAerial() async {
        await actions.nextAerial()
    }

    func nextInSubcategory() async {
        await actions.nextInSubcategory()
    }

    private func scheduledNextAerial() async {
        await actions.scheduledNextAerial()
    }

    func excludeCurrentSubcategoryAndNext() async {
        await actions.excludeCurrentSubcategoryAndNext()
    }

    func goToScreensaver() {
        actions.goToScreensaver()
    }

    func openWallpaperSettings() {
        actions.openWallpaperSettings()
    }

    func openScreenSaverSettings() {
        actions.openScreenSaverSettings()
    }

    private func bindHotkeys() {
        hotkeyCoordinator.bind(.init(
            nextAerial: { [weak self] in
                guard let self else { return }
                Task { await self.nextAerial() }
            },
            nextInSubcategory: { [weak self] in
                guard let self else { return }
                Task { await self.nextInSubcategory() }
            },
            excludeCurrentSubcategoryAndNext: { [weak self] in
                guard let self else { return }
                Task { await self.excludeCurrentSubcategoryAndNext() }
            },
            togglePause: { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    self.setRotationEnabled(self.isPaused)
                }
            },
            goToScreensaver: { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    self.goToScreensaver()
                }
            }
        ))
    }

    private func startPowerEventObservation() {
        powerEventCoordinator.start { [weak self] event in
            guard let self else { return }
            await self.handlePowerEvent(event)
        }
    }

    private func handlePowerEvent(_ event: PowerEvent) async {
        switch event {
        case .willSleep, .screensDidSleep:
            await rotationCoordinator.hibernate()
            await excludedAerialsCleanupCoordinator.hibernate()
        case .didWake, .screensDidWake:
            await rotationCoordinator.resume(behavior: settings.sleepResumeBehavior)
            await excludedAerialsCleanupCoordinator.resume()
        }
    }

    func cleanExcludedAerialsNow() {
        actions.cleanExcludedAerialsNow()
    }

    func loadDiagnosticsSnapshot() async throws -> DiagnosticsSnapshot {
        try await diagnosticsSnapshotLoader.load(settings: settings)
    }

    private func reconcileLaunchAtLoginSetting() {
        let actualEnabled = launchAtLoginCoordinator.reconciledSettingValue()

        if settingsStore.settings.launchAtLogin != actualEnabled {
            settingsStore.settings.launchAtLogin = actualEnabled
        }
    }
}

