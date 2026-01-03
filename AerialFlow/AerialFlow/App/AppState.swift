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
    private let categoryResolver: CategoryResolver
    private let storeEditor: WallpaperStoreEditor
    private let reloader: any WallpaperReloading
    private let stateStore: any AerialEngineStateStore
    private let runGuard: any RunGuarding
    private let screensaverLauncher: any ScreensaverLaunching
    private let hotkeyBinder: any HotkeyBinding
    private let launchAtLoginManager: any LaunchAtLoginManaging
    private let engine: AerialEngine
    private let tipJarPurchaserImpl: any TipJarPurchasing
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

    enum SettingsTab: Hashable, Sendable {
        case general
        case rotation
        case categories
        case hotkeys
        case diagnostics
        case about
    }

    @Published var selectedSettingsTab: SettingsTab = .general

    @Published private(set) var isBusy: Bool
    @Published private(set) var statusLine: String
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var launchAtLoginErrorMessage: String?

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
        self.tipJarPurchaserImpl = dependencies.tipJarPurchaser

        reconcileLaunchAtLoginSetting()
        bindHotkeys()
        Task { await rotationController.start() }
        
        // Update status line with current asset name if available
        Task {
            if let lastAssetID = await stateStore.getLastAssetID(), !lastAssetID.isEmpty {
                if let displayName = await assetDisplayName(for: lastAssetID) {
                    statusLine = displayName
                }
            }
        }
    }

    var isRotationEnabled: Bool { settings.isRotationEnabled }
    var isPaused: Bool { !settings.isRotationEnabled }
    var tipJarPurchaser: any TipJarPurchasing { tipJarPurchaserImpl }

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
            let displayName = await assetDisplayName(for: report.chosenAssetID) ?? report.chosenAssetID
            statusLine = displayName
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
            let report = try await engine.next(settings: settings)
            let displayName = await assetDisplayName(for: report.chosenAssetID) ?? report.chosenAssetID
            statusLine = displayName
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
        let eligible = snapshot.assets
            .filter { asset in
                guard !asset.id.isEmpty else { return false }
                if excludedMain.isEmpty, excludedSub.isEmpty { return true }
                return !asset.isExcluded(
                    excludedMainCategoryIDs: excludedMain,
                    excludedSubcategoryIDs: excludedSub
                )
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

