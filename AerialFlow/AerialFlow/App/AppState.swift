import Combine
import Foundation
import AppKit
import os
import UserNotifications

@MainActor
final class AppState: ObservableObject {
    private let logger = Logger(subsystem: "com.secondarrow.AerialFlow", category: "AppState")

    private let userDefaults: UserDefaults
    private let fileSystem: any FileSystem
    private let directoryDetector: ActiveVideoDirectoryDetector
    private let catalog: any AerialCataloging
    private let categoryResolver: CategoryResolver
    private let storeEditor: WallpaperStoreEditor
    private let reloader: any WallpaperReloading
    private let stateStore: any AerialEngineStateStore
    private let runGuard: any RunGuarding
    private let screensaverLauncher: any ScreensaverLaunching
    private let hotkeyBinder: any HotkeyBinding
    private let launchAtLoginManager: any LaunchAtLoginManaging
    private let engine: AerialEngine
    private var didRequestNotificationAuthorization = false

    private lazy var rotationController: RotationController = {
        RotationController(
            stateStore: stateStore,
            runGuard: runGuard,
            settings: settings,
            onDue: { [weak self] in
                guard let self else { return }
                await self.scheduledNextAerial()
            }
        )
    }()

    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save(to: userDefaults)
            Task { await rotationController.updateSettings(settings) }
        }
    }

    @Published private(set) var isBusy: Bool
    @Published private(set) var statusLine: String
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var launchAtLoginErrorMessage: String?

    struct DiagnosticsSnapshot: Sendable, Equatable {
        let detectedVideoDirectory: URL?
        let currentMovPath: URL?
        let lastAssetID: String?
        let lastChange: Date?
        let backupCount: Int
        let recentBackupFileNames: [String]

        var lastChangeDescription: String? {
            guard let lastChange else { return nil }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.string(from: lastChange)
        }
    }

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
        self.runGuard = dependencies.runGuard
        self.screensaverLauncher = dependencies.screensaverLauncher
        self.hotkeyBinder = dependencies.hotkeyBinder
        self.launchAtLoginManager = dependencies.launchAtLoginManager
        self.engine = dependencies.engine

        reconcileLaunchAtLoginSetting()
        bindHotkeys()
        Task { await rotationController.start() }
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
        guard !isBusy else { return }

        isBusy = true
        lastErrorMessage = nil
        statusLine = "Applying next Aerial…"
        defer { isBusy = false }

        do {
            let report = try await engine.next(settings: settings)
            var parts: [String] = []
            parts.append("Applied.")
            if report.didDownload { parts.append("Downloaded.") }
            parts.append("Updated \(report.updatedProviderNodes) nodes.")
            statusLine = parts.joined(separator: " ")
            await rotationController.notifyStateChanged()
        } catch {
            let message = error.localizedDescription
            lastErrorMessage = message
            statusLine = "Error: \(message)"
            logger.error("Next Aerial failed: \(message, privacy: .public)")
            await postErrorNotificationIfPossible(message)
        }
    }

    private func scheduledNextAerial() async {
        guard !isBusy else { return }

        isBusy = true
        defer { isBusy = false }

        do {
            _ = try await engine.next(settings: settings)
            await rotationController.notifyStateChanged()
        } catch {
            let message = error.localizedDescription
            lastErrorMessage = message
            statusLine = "Error: \(message)"
            logger.error("Scheduled rotation failed: \(message, privacy: .public)")
        }
    }

    func goToScreensaver() {
        do {
            try screensaverLauncher.start()
            statusLine = "Starting screensaver…"
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

    func loadCatalogSnapshot() async throws -> AerialCatalog.Snapshot {
        try await catalog.loadSnapshot()
    }

    func categoryDisplayNamesByID(categories: [AerialCategory]) -> [String: String] {
        let idToNames = categoryResolver.categoryIDToNames(categories: categories)
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

    func openSystemSettingsForWallpaper() {
        let workspace = NSWorkspace.shared
        if let url = URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension"),
           workspace.open(url) {
            return
        }
        if let url = URL(string: "x-apple.systempreferences:") {
            _ = workspace.open(url)
        }
    }

    func loadDiagnosticsSnapshot() async throws -> DiagnosticsSnapshot {
        let indexPlistURL = settings.indexPlistURL
        let fileSystem = self.fileSystem
        let detector = self.directoryDetector

        async let lastAssetID = stateStore.getLastAssetID()
        async let lastChange = stateStore.getLastChange()

        let detection = try detector.detect()
        let backups = Self.findIndexPlistBackups(fileSystem: fileSystem, indexPlistURL: indexPlistURL)

        let recentNames = backups.prefix(5).map(\.lastPathComponent)

        return DiagnosticsSnapshot(
            detectedVideoDirectory: detection.videoDirectory,
            currentMovPath: detection.currentMovPath,
            lastAssetID: await lastAssetID,
            lastChange: await lastChange,
            backupCount: backups.count,
            recentBackupFileNames: recentNames
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

    private func desiredAssetIDForConfigurationRepair() async throws -> String {
        if let last = await stateStore.getLastAssetID(), !last.isEmpty {
            return last
        }

        let snapshot = try await loadCatalogSnapshot()
        let excluded = settings.excludedCategoryIDs
        let eligible = snapshot.assets
            .filter { asset in
                guard !asset.id.isEmpty else { return false }
                if excluded.isEmpty { return true }
                return excluded.isDisjoint(with: Set(asset.categories))
            }
            .sorted { $0.id < $1.id }

        guard let first = eligible.first else {
            throw AssetPicker.PickerError.noEligibleAssets
        }
        return first.id
    }

    private func postErrorNotificationIfPossible(_ message: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            guard !didRequestNotificationAuthorization else { return }
            didRequestNotificationAuthorization = true
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                guard granted else { return }
            } catch {
                logger.debug("Notification authorization request failed: \(String(describing: error), privacy: .public)")
                return
            }
        case .authorized, .provisional, .ephemeral:
            break
        case .denied:
            return
        @unknown default:
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "AerialFlow Error"
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        await withCheckedContinuation { continuation in
            center.add(request) { error in
                if let error {
                    self.logger.debug("Failed to post notification: \(String(describing: error), privacy: .public)")
                }
                continuation.resume()
            }
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

