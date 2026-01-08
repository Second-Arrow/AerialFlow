import Combine
import Foundation
import AppKit
import os
import UserNotifications

@MainActor
final class AppState: ObservableObject {
    private enum NextAerialError: LocalizedError {
        case busy

        var errorDescription: String? {
            switch self {
            case .busy:
                return "AerialFlow is busy."
            }
        }
    }

    private enum NextInSubcategoryError: LocalizedError {
        case busy
        case noCurrentSubcategory
        case noEligibleAssetsInSubcategory

        var errorDescription: String? {
            switch self {
            case .busy:
                return "AerialFlow is busy."
            case .noCurrentSubcategory:
                return "No current subcategory is available for the active Aerial."
            case .noEligibleAssetsInSubcategory:
                return "No eligible Aerial assets are available in the current subcategory."
            }
        }
    }

    private let logger = Logger(subsystem: Constants.loggerSubsystem, category: "AppState")

    private let userDefaults: UserDefaults
    private let fileSystem: any FileSystem
    private let directoryDetector: ActiveVideoDirectoryDetector
    private let catalog: any AerialCataloging
    private let categoryResolver: CategoryResolver
    private let storeEditor: WallpaperStoreEditor
    private let reloader: any WallpaperReloading
    private let stateStore: any AerialEngineStateStore
    private let excludedAerialsCleanupStateStore: any ExcludedAerialsCleanupStateStoring
    private let powerEventObserver: any PowerEventObserving
    private let screensaverLauncher: any ScreensaverLaunching
    private let hotkeyBinder: any HotkeyBinding
    private let launchAtLoginManager: any LaunchAtLoginManaging
    private let excludedAerialsCleaner: ExcludedAerialsCleaner
    private let engine: AerialEngine
    private let brightnessStore: any AerialBrightnessStoring
    let updaterViewModel: UpdaterViewModel
    private let systemAccessProbe: any SystemAccessProbing
    private let notificationPermissionService: any NotificationPermissionServicing
    private let systemSettingsOpener: any SystemSettingsOpening
    private var powerEventTask: Task<Void, Never>?
    private var errorNotificationTask: Task<Void, Never>?
    private var excludedAerialsCleanupTask: Task<Void, Never>?
    private var brightnessPrecomputeTask: Task<Void, Never>?

    private lazy var rotationController: RotationController = {
        RotationController(
            stateStore: stateStore,
            settings: settings,
            onDue: { [weak self] in
                guard let self else { return }
                await self.scheduledNextAerial()
            }
        )
    }()

    private lazy var excludedAerialsCleanupController: ExcludedAerialsCleanupController = {
        ExcludedAerialsCleanupController(
            stateStore: excludedAerialsCleanupStateStore,
            settings: settings,
            onDue: { [weak self] in
                guard let self else { return false }
                return await self.scheduledExcludedAerialCleanup()
            }
        )
    }()

    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save(to: userDefaults)
            Task { await rotationController.updateSettings(settings) }
            Task { await excludedAerialsCleanupController.updateSettings(settings) }
            refreshSystemAccessReport()
        }
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

    @Published var selectedSettingsDestination: SettingsDestination = .general

    @Published private(set) var isBusy: Bool
    @Published private(set) var statusLine: String
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var launchAtLoginErrorMessage: String?
    @Published private(set) var isCleaningExcludedAerials: Bool = false
    @Published private(set) var systemAccessReport: SystemAccessReport?
    @Published private(set) var notificationAuthorizationStatus: UNAuthorizationStatus?
    @Published private(set) var onboardingRequested: Bool = false

    private let onboardingUserDefaultsKey = "AerialFlow.didShowOnboarding"

    init(dependencies: AppDependencies, userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let settingsSnapshot = AppSettings.load(from: userDefaults)
        self.settings = settingsSnapshot

        self.isBusy = false
        self.statusLine = "Ready"
        self.lastErrorMessage = nil
        self.launchAtLoginErrorMessage = nil

        self.fileSystem = dependencies.fileSystem
        self.directoryDetector = dependencies.directoryDetector
        self.catalog = dependencies.catalog
        self.categoryResolver = dependencies.categoryResolver
        self.storeEditor = dependencies.storeEditor
        self.reloader = dependencies.reloader
        self.stateStore = dependencies.stateStore
        self.excludedAerialsCleanupStateStore = dependencies.excludedAerialsCleanupStateStore
        self.powerEventObserver = dependencies.powerEventObserver
        self.screensaverLauncher = dependencies.screensaverLauncher
        self.hotkeyBinder = dependencies.hotkeyBinder
        self.launchAtLoginManager = dependencies.launchAtLoginManager
        self.excludedAerialsCleaner = dependencies.excludedAerialsCleaner
        self.engine = dependencies.engine
        self.brightnessStore = dependencies.brightnessStore
        self.updaterViewModel = dependencies.updaterViewModel
        self.systemAccessProbe = dependencies.systemAccessProbe
        self.notificationPermissionService = dependencies.notificationPermissionService
        self.systemSettingsOpener = dependencies.systemSettingsOpener

        reconcileLaunchAtLoginSetting()
        bindHotkeys()
        Task { await rotationController.start() }
        Task { await excludedAerialsCleanupController.updateSettings(settingsSnapshot) }
        startPowerEventObservation()
        startBrightnessPrecompute()
        refreshSystemAccessReport()
        if NSClassFromString("XCTestCase") == nil {
            Task { await refreshNotificationAuthorizationStatus() }
        }

        if !userDefaults.bool(forKey: onboardingUserDefaultsKey) {
            userDefaults.set(true, forKey: onboardingUserDefaultsKey)
            onboardingRequested = true
        }
        
        // Update status line with current asset name if available.
        // Avoid overwriting any user-initiated status updates that may occur shortly after init.
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.statusLine == "Ready", self.lastErrorMessage == nil else { return }
            guard let lastAssetID = await stateStore.getLastAssetID(), !lastAssetID.isEmpty else { return }
            guard let displayName = await assetDisplayName(for: lastAssetID) else { return }
            guard self.statusLine == "Ready", self.lastErrorMessage == nil else { return }
            self.statusLine = displayName
        }
    }

    func refreshSystemAccessReport() {
        let settingsSnapshot = settings
        Task.detached { [weak self, systemAccessProbe] in
            let report = systemAccessProbe.probe(settings: settingsSnapshot)
            await MainActor.run { [weak self, report] in
                self?.systemAccessReport = report
                if report.items.contains(where: { $0.state != .ok }) {
                    self?.onboardingRequested = true
                }
            }
        }
    }

    func consumeOnboardingRequest() -> Bool {
        if onboardingRequested {
            onboardingRequested = false
            return true
        }
        return false
    }

    func refreshNotificationAuthorizationStatus() async {
        let status = await notificationPermissionService.authorizationStatus()
        notificationAuthorizationStatus = status
    }

    func requestNotificationAuthorization() {
        Task { [weak self] in
            _ = await self?.notificationPermissionService.requestAuthorization()
            await self?.refreshNotificationAuthorizationStatus()
        }
    }

    func openNotificationSettings() {
        _ = systemSettingsOpener.openNotificationsSettings()
    }

    func openLoginItemsSettings() {
        _ = systemSettingsOpener.openLoginItemsSettings()
    }

    func openInputMonitoringSettings() {
        _ = systemSettingsOpener.openInputMonitoringSettings()
    }

    func openAccessibilitySettings() {
        _ = systemSettingsOpener.openAccessibilitySettings()
    }

    func openSystemSettings() {
        _ = systemSettingsOpener.openSystemSettings()
    }

    deinit {
        // Cleanup tasks owned by AppState.menu
        powerEventTask?.cancel()
        errorNotificationTask?.cancel()
        excludedAerialsCleanupTask?.cancel()
        brightnessPrecomputeTask?.cancel()
    }

    var isRotationEnabled: Bool { settings.isRotationEnabled }
    var isPaused: Bool { !settings.isRotationEnabled }

    func setRotationEnabled(_ enabled: Bool) {
        guard settings.isRotationEnabled != enabled else { return }
        settings.isRotationEnabled = enabled
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        let previous = settings.launchAtLogin
        guard previous != enabled else { return }

        // Optimistically update UI; revert if system registration fails or needs approval.
        settings.launchAtLogin = enabled
        launchAtLoginErrorMessage = nil

        do {
            if enabled {
                try launchAtLoginManager.register()
            } else {
                try launchAtLoginManager.unregister()
            }
        } catch {
            settings.launchAtLogin = previous
            launchAtLoginErrorMessage = launchAtLoginFailureMessage(for: error)
            return
        }

        // ServiceManagement may require the user to approve the login item.
        switch launchAtLoginManager.status() {
        case .enabled:
            launchAtLoginErrorMessage = nil
        case .disabled:
            if enabled {
                settings.launchAtLogin = previous
                launchAtLoginErrorMessage = launchAtLoginFailureMessage(for: nil)
            } else {
                launchAtLoginErrorMessage = nil
            }
        case .requiresApproval:
            settings.launchAtLogin = previous
            launchAtLoginErrorMessage = "macOS requires approval. Enable AerialFlow in System Settings > General > Login Items."
        }
    }

    func nextAerial() async {
        _ = await performNextAerial(isUserInitiated: true, logContext: "Next Aerial")
    }

    func nextInSubcategory() async {
        guard !isBusy else {
            await handleUserInitiatedError(NextInSubcategoryError.busy, logContext: "Next In Subcategory")
            return
        }

        isBusy = true
        lastErrorMessage = nil
        statusLine = "Applying next in subcategory…"
        defer { isBusy = false }

        let subcategoryIDs = await currentSubcategoryIDs()
        guard let primarySubcategoryID = subcategoryIDs.sorted().first else {
            await handleUserInitiatedError(NextInSubcategoryError.noCurrentSubcategory, logContext: "Next In Subcategory")
            return
        }

        do {
            let report = try await engine.nextInSubcategory(settings: settings, subcategoryID: primarySubcategoryID)
            let displayName = await assetDisplayName(for: report.chosenAssetID) ?? report.chosenAssetID
            statusLine = displayName
            await rotationController.notifyStateChanged()
        } catch {
            let isNoEligibleAssets: Bool
            if let pickerError = error as? AssetPicker.PickerError, case .noEligibleAssets = pickerError {
                isNoEligibleAssets = true
            } else {
                isNoEligibleAssets = (error.localizedDescription == AssetPicker.PickerError.noEligibleAssets.localizedDescription)
            }

            if isNoEligibleAssets {
                await handleUserInitiatedError(NextInSubcategoryError.noEligibleAssetsInSubcategory, logContext: "Next In Subcategory")
            } else {
                await handleUserInitiatedError(error, logContext: "Next In Subcategory")
            }
        }
    }

    private func scheduledNextAerial() async {
        _ = await performNextAerial(isUserInitiated: false, logContext: "Scheduled rotation")
    }

    private func handleUserInitiatedError(_ error: Error, logContext: String) async {
        let message = error.localizedDescription
        lastErrorMessage = message
        statusLine = "Error: \(message)"
        logger.error("\(logContext) failed: \(message, privacy: .public)")
        scheduleErrorNotificationIfPossible(message)
    }

    /// Advances to the next Aerial.
    /// - Parameters:
    ///   - isUserInitiated: If true, clears error state beforehand and posts notifications on failure.
    ///   - logContext: Context string for error logging (e.g., "Next Aerial" or "Scheduled rotation").
    private func performNextAerial(isUserInitiated: Bool, logContext: String) async -> Result<AerialEngine.Report, Error> {
        guard !isBusy else { return .failure(NextAerialError.busy) }

        isBusy = true
        if isUserInitiated {
            lastErrorMessage = nil
            statusLine = "Applying next Aerial…"
        }
        defer { isBusy = false }

        do {
            let report = try await engine.next(settings: settings)
            let displayName = await assetDisplayName(for: report.chosenAssetID) ?? report.chosenAssetID
            statusLine = displayName
            await rotationController.notifyStateChanged()
            return .success(report)
        } catch {
            let message = error.localizedDescription
            lastErrorMessage = message
            statusLine = "Error: \(message)"
            logger.error("\(logContext) failed: \(message, privacy: .public)")
            if isUserInitiated {
                scheduleErrorNotificationIfPossible(message)
            }
            return .failure(error)
        }
    }

    func excludeCurrentSubcategoryAndNext() async {
        guard !isBusy else { return }

        let previous = settings.excludedAssetIDs
        if let currentAssetID = await stateStore.getLastAssetID(), !currentAssetID.isEmpty {
            var updated = settings.excludedAssetIDs
            updated.insert(currentAssetID)
            settings.excludedAssetIDs = updated
        }

        let result = await performNextAerial(isUserInitiated: true, logContext: "Exclude current aerial + Next")
        if case .failure(let error) = result {
            let isNoEligibleAssets: Bool
            if let pickerError = error as? AssetPicker.PickerError, case .noEligibleAssets = pickerError {
                isNoEligibleAssets = true
            } else {
                // Be resilient to error type wrapping/bridging while still keying off the specific condition.
                isNoEligibleAssets = (error.localizedDescription == AssetPicker.PickerError.noEligibleAssets.localizedDescription)
            }

            if isNoEligibleAssets {
                settings.excludedAssetIDs = previous
            }
        }
    }

    func goToScreensaver() {
        do {
            try screensaverLauncher.start()
        } catch {
            let message = error.localizedDescription
            lastErrorMessage = message
            statusLine = "Error: \(message)"
            logger.error("Go To Screensaver failed: \(message, privacy: .public)")
        }
    }

    private func bindHotkeys() {
        hotkeyBinder.onKeyUp(for: .nextAerial) { [weak self] in
            guard let self else { return }
            Task { await self.nextAerial() }
        }

        hotkeyBinder.onKeyUp(for: .nextInSubcategory) { [weak self] in
            guard let self else { return }
            Task { await self.nextInSubcategory() }
        }

        hotkeyBinder.onKeyUp(for: .excludeCurrentSubcategoryAndNext) { [weak self] in
            guard let self else { return }
            Task { await self.excludeCurrentSubcategoryAndNext() }
        }

        hotkeyBinder.onKeyUp(for: .togglePause) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.setRotationEnabled(self.isPaused)
            }
        }

        hotkeyBinder.onKeyUp(for: .goToScreensaver) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.goToScreensaver()
            }
        }
    }

    private func startPowerEventObservation() {
        powerEventTask?.cancel()
        powerEventTask = Task { [weak self] in
            guard let self else { return }
            for await event in powerEventObserver.events() {
                await self.handlePowerEvent(event)
            }
        }
    }

    private func startBrightnessPrecompute() {
        brightnessPrecomputeTask?.cancel()

        let catalog = self.catalog
        let store = self.brightnessStore
        let logger = Logger(subsystem: Constants.loggerSubsystem, category: "BrightnessPrecompute")

        brightnessPrecomputeTask = Task.detached(priority: .background) {
            guard !Task.isCancelled else { return }
            do {
                let snapshot = try await catalog.loadSnapshot()
                guard !Task.isCancelled else { return }
                await store.precompute(assets: snapshot.assets, timeout: 2, maxConcurrency: 4)
            } catch {
                logger.debug("Brightness precompute skipped: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func handlePowerEvent(_ event: PowerEvent) async {
        switch event {
        case .willSleep, .screensDidSleep:
            await rotationController.hibernate()
            await excludedAerialsCleanupController.hibernate()
        case .didWake, .screensDidWake:
            await rotationController.resume(behavior: settings.sleepResumeBehavior)
            await excludedAerialsCleanupController.resume()
        }
    }

    func cleanExcludedAerialsNow() {
        excludedAerialsCleanupTask?.cancel()
        excludedAerialsCleanupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runUserInitiatedExcludedAerialCleanup()
        }
    }

    private func runUserInitiatedExcludedAerialCleanup() async {
        guard !isCleaningExcludedAerials else { return }

        isCleaningExcludedAerials = true
        lastErrorMessage = nil
        statusLine = "Cleaning excluded Aerials…"
        defer { isCleaningExcludedAerials = false }

        do {
            let report = try await excludedAerialsCleaner.cleanExcludedMovFiles(settings: settings)
            if !report.failures.isEmpty {
                let message = "Cleaned: removed \(report.removedCount) file(s), failed \(report.failures.count)."
                lastErrorMessage = message
                statusLine = "Error: \(message)"
                logger.error("Clean Now failed for some files: \(message, privacy: .public)")
                scheduleErrorNotificationIfPossible(message)
            } else if report.removedCount == 0 {
                statusLine = "No excluded files to remove."
            } else {
                statusLine = "Removed \(report.removedCount) excluded file(s)."
            }
        } catch {
            await handleUserInitiatedError(error, logContext: "Clean Now")
        }
    }

    /// Scheduled daily auto-cleanup (does not post user notifications).
    private func scheduledExcludedAerialCleanup() async -> Bool {
        guard !isCleaningExcludedAerials else {
            logger.debug("Scheduled excluded-aerial cleanup skipped: already running.")
            return false
        }

        do {
            let report = try await excludedAerialsCleaner.cleanExcludedMovFiles(settings: settings)
            if report.failures.isEmpty {
                return true
            }
            logger.error("Scheduled excluded-aerial cleanup had failures: failed=\(report.failures.count, privacy: .public)")
            return false
        } catch {
            logger.error("Scheduled excluded-aerial cleanup failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    func loadCatalogSnapshot() async throws -> AerialCatalog.Snapshot {
        try await catalog.loadSnapshot()
    }

    func categoryDisplayNamesByID(categories: [AerialCategory]) async -> [String: String] {
        let idToNames = await categoryResolver.categoryIDToNames(categories: categories)
        var out: [String: String] = [:]
        out.reserveCapacity(categories.count)

        for category in categories {
            guard !category.id.isEmpty else { continue }
            let names = idToNames[category.id] ?? []
            let best = names
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                .first
            out[category.id] = best ?? category.id
        }

        return out
    }

    func assetDisplayNamesByID(assets: [AerialAsset]) async -> [String: String] {
        let strings = await categoryResolver.loadAllLocalizedStrings()

        var out: [String: String] = [:]
        out.reserveCapacity(assets.count)

        for asset in assets {
            guard !asset.id.isEmpty else { continue }

            if let key = asset.localizedNameKey, !key.isEmpty,
               let values = strings[key], !values.isEmpty {
                let best = values
                    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                    .first
                out[asset.id] = best ?? asset.id
            } else {
                out[asset.id] = asset.id
            }
        }

        return out
    }

    func currentAssetID() async -> String? {
        await stateStore.getLastAssetID()
    }

    /// Returns the subcategory IDs of the currently active aerial asset.
    /// Returns an empty set if no current asset or if the asset is not found in the catalog.
    func currentSubcategoryIDs() async -> Set<String> {
        guard let lastAssetID = await stateStore.getLastAssetID(), !lastAssetID.isEmpty else {
            return []
        }

        do {
            let snapshot = try await loadCatalogSnapshot()
            if let asset = snapshot.assets.first(where: { $0.id == lastAssetID }) {
                return Set(asset.subcategories)
            }
            return []
        } catch {
            logger.debug("Failed to load catalog for current subcategory IDs: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    /// Resolves an asset ID to a human-readable display name.
    /// Returns the asset's localized name (via TVIdleScreenStrings) if available, otherwise falls back to the asset ID.
    private func assetDisplayName(for assetID: String) async -> String? {
        guard !assetID.isEmpty else { return nil }

        do {
            let snapshot = try await loadCatalogSnapshot()
            if let asset = snapshot.assets.first(where: { $0.id == assetID }) {
                return await categoryResolver.assetName(for: asset) ?? assetID
            }
            return await categoryResolver.assetName(for: assetID) ?? assetID
        } catch {
            logger.debug("Failed to resolve asset display name for \(assetID, privacy: .public): \(String(describing: error), privacy: .public)")
            return assetID
        }
    }

    func inspectAerialConfiguration() throws -> WallpaperStoreEditor.AerialConfigurationStatus {
        try storeEditor.inspectAerialConfiguration(indexPlistURL: settings.indexPlistURL)
    }

    func repairAerialConfiguration() async throws -> WallpaperStoreEditor.AerialConfigurationRepairReport {
        let desiredAssetID = try await desiredAssetIDForConfigurationRepair()
        let report = try storeEditor.repairAerialConfiguration(
            desiredAssetID: desiredAssetID,
            indexPlistURL: settings.indexPlistURL,
            backupRetentionCount: settings.backupRetentionCount
        )
        reloader.reloadWallpaperPipelines()
        return report
    }

    func loadDiagnosticsSnapshot() async throws -> DiagnosticsSnapshot {
        let indexPlistURL = settings.indexPlistURL
        let fileSystem = self.fileSystem
        let detector = self.directoryDetector

        async let lastAssetID = stateStore.getLastAssetID()
        async let lastChange = stateStore.getLastChange()
        async let nextScheduledChangeDate = rotationController.nextScheduledChangeDate()

        let detection = try detector.detect()
        let backups = Self.findIndexPlistBackups(fileSystem: fileSystem, indexPlistURL: indexPlistURL)

        let recentNames = backups.prefix(5).map(\.lastPathComponent)
        
        let storageUsedBytes = Self.calculateStorageUsed(fileSystem: fileSystem, videoDirectory: detection.videoDirectory)
        
        let resolvedLastAssetID = await lastAssetID
        
        // Fallback: if process detection didn't find a mov path, try to construct it from last asset ID
        let currentMovPath = detection.currentMovPath ?? Self.fallbackMovPath(
            fileSystem: fileSystem,
            videoDirectory: detection.videoDirectory,
            lastAssetID: resolvedLastAssetID
        )

        return DiagnosticsSnapshot(
            detectedVideoDirectory: detection.videoDirectory,
            currentMovPath: currentMovPath,
            lastAssetID: resolvedLastAssetID,
            lastChange: await lastChange,
            nextScheduledChangeDate: await nextScheduledChangeDate,
            backupCount: backups.count,
            recentBackupFileNames: recentNames,
            storageUsedBytes: storageUsedBytes
        )
    }

    nonisolated private static func findIndexPlistBackups(fileSystem: any FileSystem, indexPlistURL: URL) -> [URL] {
        let dir = indexPlistURL.deletingLastPathComponent()
        let prefix = "\(indexPlistURL.lastPathComponent)."

        let files: [URL]
        do {
            files = try fileSystem.listFiles(in: dir)
        } catch {
            return []
        }

        // Backups are named like: Index.plist.YYYYMMDD-HHmmss.bak
        let backups = files.filter { url in
            let name = url.lastPathComponent
            return name.hasPrefix(prefix) && name.hasSuffix(".bak")
        }

        // Timestamp format sorts lexicographically, so name-desc gives newest-first.
        return backups.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    nonisolated static func fallbackMovPath(fileSystem: any FileSystem, videoDirectory: URL, lastAssetID: String?) -> URL? {
        guard let assetID = lastAssetID, !assetID.isEmpty else { return nil }
        let movPath = videoDirectory.appendingPathComponent("\(assetID).mov")
        guard fileSystem.fileExists(at: movPath) else { return nil }
        return movPath
    }

    nonisolated static func calculateStorageUsed(fileSystem: any FileSystem, videoDirectory: URL) -> Int64? {
        guard fileSystem.fileExists(at: videoDirectory) else {
            return nil
        }

        let files: [URL]
        do {
            files = try fileSystem.listFiles(in: videoDirectory)
        } catch {
            return nil
        }

        // Filter for .mov files, excluding .part files
        let movFiles = files.filter { url in
            let name = url.lastPathComponent
            return name.hasSuffix(".mov") && !name.hasPrefix(".")
        }

        var totalBytes: Int64 = 0
        for file in movFiles {
            do {
                let size = try fileSystem.fileSize(at: file)
                totalBytes += size
            } catch {
                // Skip files we can't read the size of
                continue
            }
        }

        return totalBytes
    }

    private func desiredAssetIDForConfigurationRepair() async throws -> String {
        if let last = await stateStore.getLastAssetID(), !last.isEmpty {
            return last
        }

        let snapshot = try await loadCatalogSnapshot()
        let excludedMain = settings.excludedCategoryIDs
        let excludedSub = settings.excludedSubcategoryIDs
        let excludedAssets = settings.excludedAssetIDs
        let eligible = snapshot.assets
            .filter { asset in
                guard !asset.id.isEmpty else { return false }
                if excludedMain.isEmpty, excludedSub.isEmpty, excludedAssets.isEmpty { return true }
                return !asset.isExcluded(
                    excludedMainCategoryIDs: excludedMain,
                    excludedSubcategoryIDs: excludedSub,
                    excludedAssetIDs: excludedAssets
                )
            }
            .sorted { $0.id < $1.id }

        guard let first = eligible.first else {
            throw AssetPicker.PickerError.noEligibleAssets
        }
        return first.id
    }

    private func scheduleErrorNotificationIfPossible(_ message: String) {
        errorNotificationTask?.cancel()
        errorNotificationTask = Task { [weak self] in
            guard let self else { return }
            await self.notificationPermissionService.postErrorNotificationIfPossible(message)
            await self.refreshNotificationAuthorizationStatus()
        }
    }

    private func reconcileLaunchAtLoginSetting() {
        let actualEnabled: Bool
        switch launchAtLoginManager.status() {
        case .enabled:
            actualEnabled = true
        case .disabled, .requiresApproval:
            actualEnabled = false
        }

        if settings.launchAtLogin != actualEnabled {
            settings.launchAtLogin = actualEnabled
        }
    }

    private func launchAtLoginFailureMessage(for error: Error?) -> String {
        if let error {
            return "Couldn’t update Launch at login: \(error.localizedDescription). You can also enable it in System Settings > General > Login Items."
        }
        return "Couldn’t enable Launch at login. You can enable it in System Settings > General > Login Items."
    }
}

