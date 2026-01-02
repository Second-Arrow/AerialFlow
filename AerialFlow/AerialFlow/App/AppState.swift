import Combine
import Foundation
import AppKit
import os
import UserNotifications

@MainActor
final class AppState: ObservableObject {
    private let logger = Logger(subsystem: "com.secondarrow.AerialFlow", category: "AppState")

    private let userDefaults: UserDefaults
    private let catalog: AerialCatalog
    private let categoryResolver: CategoryResolver
    private let storeEditor: WallpaperStoreEditor
    private let reloader: WallpaperReloader
    private let stateStore: UserDefaultsEngineStateStore
    private var engine: AerialEngine
    private var didRequestNotificationAuthorization = false

    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save(to: userDefaults)
            engine = makeEngine(settings: settings)
        }
    }

    @Published private(set) var isBusy: Bool
    @Published private(set) var statusLine: String
    @Published private(set) var lastErrorMessage: String?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let settingsSnapshot = AppSettings.load(from: userDefaults)
        self.settings = settingsSnapshot

        self.isBusy = false
        self.statusLine = "Ready"
        self.lastErrorMessage = nil

        let runner = ProcessCommandRunner()
        let catalog = AerialCatalog()
        let categoryResolver = CategoryResolver()
        let picker = AssetPicker()
        let urlSelector = AssetURLSelector()
        let directoryDetector = ActiveVideoDirectoryDetector(runner: runner)
        let downloader = AssetDownloader(directoryDetector: directoryDetector)
        let storeEditor = WallpaperStoreEditor()
        let reloader = WallpaperReloader(runner: runner)
        let stateStore = UserDefaultsEngineStateStore(userDefaults: userDefaults)

        self.catalog = catalog
        self.categoryResolver = categoryResolver
        self.storeEditor = storeEditor
        self.reloader = reloader
        self.stateStore = stateStore

        self.engine = AerialEngine(
            catalog: catalog,
            categoryResolver: categoryResolver,
            picker: picker,
            urlSelector: urlSelector,
            downloader: downloader,
            storeEditor: storeEditor,
            reloader: reloader,
            settings: settingsSnapshot,
            stateStore: stateStore
        )
    }

    var isRotationEnabled: Bool { settings.isRotationEnabled }
    var isPaused: Bool { !settings.isRotationEnabled }

    func setRotationEnabled(_ enabled: Bool) {
        guard settings.isRotationEnabled != enabled else { return }
        settings.isRotationEnabled = enabled
    }

    func nextAerial() async {
        guard !isBusy else { return }

        isBusy = true
        lastErrorMessage = nil
        statusLine = "Applying next Aerial…"
        defer { isBusy = false }

        do {
            engine = makeEngine(settings: settings)
            let report = try await engine.next(manual: true)
            var parts: [String] = []
            parts.append("Applied.")
            if report.didDownload { parts.append("Downloaded.") }
            parts.append("Updated \(report.updatedProviderNodes) nodes.")
            statusLine = parts.joined(separator: " ")
        } catch {
            let message = error.localizedDescription
            lastErrorMessage = message
            statusLine = "Error: \(message)"
            logger.error("Next Aerial failed: \(message, privacy: .public)")
            await postErrorNotificationIfPossible(message)
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
            indexPlistURL: settings.indexPlistURL
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
            throw AerialEngine.EngineError.noEligibleAssets
        }
        return first.id
    }

    private func makeEngine(settings: AppSettings) -> AerialEngine {
        let picker = AssetPicker()
        let urlSelector = AssetURLSelector()
        let runner = ProcessCommandRunner()
        let directoryDetector = ActiveVideoDirectoryDetector(runner: runner)
        let downloader = AssetDownloader(directoryDetector: directoryDetector)
        return AerialEngine(
            catalog: catalog,
            categoryResolver: categoryResolver,
            picker: picker,
            urlSelector: urlSelector,
            downloader: downloader,
            storeEditor: storeEditor,
            reloader: reloader,
            settings: settings,
            stateStore: stateStore
        )
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
}

