import Foundation
import Testing
@testable import AerialFlow

private struct FakeCatalog: AerialCataloging {
    let snapshot: AerialCatalog.Snapshot
    func loadSnapshot() async throws -> AerialCatalog.Snapshot { snapshot }
}

private struct FakeURLSelector: AssetURLSelecting {
    let url: URL
    func pickURL(for asset: AerialAsset) throws -> URL {
        _ = asset
        return url
    }
}

private struct FakeDownloader: AssetDownloadEnsuring {
    func ensureDownloaded(assetID: String, url: URL?, timeout: TimeInterval) async throws -> AssetDownloader.Result {
        _ = assetID
        _ = url
        _ = timeout
        return .init(destinationURL: URL(fileURLWithPath: "/tmp/ASSET.mov"), didDownload: false)
    }
}

private struct FakeStoreEditor: WallpaperApplying {
    func applyAerialAssetID(_ assetID: String, indexPlistURL: URL, backupRetentionCount: Int) throws -> WallpaperStoreEditor.ApplyResult {
        _ = assetID
        _ = indexPlistURL
        _ = backupRetentionCount
        return .init(updatedProviderNodeCount: 0, backupURL: URL(fileURLWithPath: "/tmp/Index.plist.bak"))
    }

    func inspectAerialConfiguration(indexPlistURL: URL) throws -> WallpaperStoreEditor.AerialConfigurationStatus {
        _ = indexPlistURL
        return .init(
            totalProviderNodes: 0,
            desktopProviderNodes: 0,
            idleProviderNodes: 0,
            issues: []
        )
    }

    func repairAerialConfiguration(
        desiredAssetID: String,
        indexPlistURL: URL,
        backupRetentionCount: Int
    ) throws -> WallpaperStoreEditor.AerialConfigurationRepairReport {
        _ = desiredAssetID
        _ = indexPlistURL
        _ = backupRetentionCount
        return .init(didUpsertProviderNodes: false, updatedProviderNodeCount: 0, backupURL: URL(fileURLWithPath: "/tmp/Index.plist.bak"))
    }
}

private struct FakeReloader: WallpaperReloading {
    func reloadWallpaperPipelines() {}
}

private struct NoopScreensaverLauncher: ScreensaverLaunching {
    func start() throws {}
}

struct AppUserActionsTests {
    enum TestError: Error {
        case couldNotCreateUserDefaultsSuite
    }

    @Test func testNextAerial_whenBusy_doesNotChangeStatusOrError() async throws {
        let suiteName = "AerialFlowTests.AppUserActions.Busy.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.couldNotCreateUserDefaultsSuite
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let fileSystem = InMemoryFileSystem()
        let runner = FakeCommandRunner()
        let stateStore = FakeEngineStateStore(lastAssetID: "b")

        let assets = [
            AerialAsset(
                id: "b",
                categories: [],
                subcategories: [],
                urlVariants: ["url-4K": URL(string: "https://example.com/b.mov")!]
            ),
        ]
        let snapshot = AerialCatalog.Snapshot(
            assets: assets,
            categories: [],
            fileURL: URL(fileURLWithPath: "/dev/null"),
            fileModificationDate: nil
        )

        let catalog = FakeCatalog(snapshot: snapshot)
        let categoryResolver = CategoryResolver(fileSystem: fileSystem)
        let catalogPresentation = CatalogPresentationService(catalog: catalog, resolver: categoryResolver)

        let engine = AerialEngine(
            catalog: catalog,
            picker: AssetPicker(),
            urlSelector: FakeURLSelector(url: URL(string: "https://example.com/any.mov")!),
            downloader: FakeDownloader(),
            brightnessStore: NoopBrightnessStore(),
            storeEditor: FakeStoreEditor(),
            reloader: FakeReloader(),
            stateStore: stateStore
        )

        let ui = await MainActor.run {
            AppUIState(isBusy: true, statusLine: "BusyStatus", lastErrorMessage: "ExistingError")
        }
        let settingsStore = await MainActor.run { [suiteName] in
            // `MainActor.run` takes a `@Sendable` closure; avoid capturing `UserDefaults` (non-Sendable).
            let defaultsForMainActor = UserDefaults(suiteName: suiteName)!
            return AppSettingsStore(userDefaults: defaultsForMainActor, initialSettings: AppSettings())
        }
        let notificationCoordinator = await MainActor.run {
            NotificationCoordinator(service: NoopNotificationPermissionService())
        }

        let rotationCoordinator = RotationCoordinator(
            stateStore: stateStore,
            engine: engine,
            initialSettings: AppSettings(),
            onDue: {}
        )
        let excludedCleaner = ExcludedAerialsCleaner(
            fileSystem: fileSystem,
            directoryDetector: ActiveVideoDirectoryDetector(runner: runner),
            catalog: catalog
        )
        let excludedCleanupCoordinator = ExcludedAerialsCleanupCoordinator(
            stateStore: FakeExcludedAerialsCleanupStateStore(),
            cleaner: excludedCleaner,
            initialSettings: AppSettings(),
            settingsProvider: { AppSettings() }
        )

        let actions = await MainActor.run {
            AppUserActions(
                ui: ui,
                settingsStore: settingsStore,
                stateStore: stateStore,
                rotationCoordinator: rotationCoordinator,
                excludedAerialsCleanupCoordinator: excludedCleanupCoordinator,
                catalogPresentation: catalogPresentation,
                screensaverLauncher: NoopScreensaverLauncher(),
                systemSettingsOpener: NoopSystemSettingsOpener(),
                notificationCoordinator: notificationCoordinator
            )
        }

        await actions.nextAerial()

        let status = await MainActor.run { ui.statusLine }
        let error = await MainActor.run { ui.lastErrorMessage }
        let busy = await MainActor.run { ui.isBusy }

        #expect(status == "BusyStatus")
        #expect(error == "ExistingError")
        #expect(busy == true)
    }

    @Test func testNextInSubcategory_noCurrentSubcategory_setsUserFacingError() async throws {
        let suiteName = "AerialFlowTests.AppUserActions.NoSubcategory.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.couldNotCreateUserDefaultsSuite
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let fileSystem = InMemoryFileSystem()
        let runner = FakeCommandRunner()
        let stateStore = FakeEngineStateStore(lastAssetID: "b")

        let assets = [
            AerialAsset(
                id: "b",
                categories: [],
                subcategories: [],
                urlVariants: ["url-4K": URL(string: "https://example.com/b.mov")!]
            ),
        ]
        let snapshot = AerialCatalog.Snapshot(
            assets: assets,
            categories: [],
            fileURL: URL(fileURLWithPath: "/dev/null"),
            fileModificationDate: nil
        )

        let catalog = FakeCatalog(snapshot: snapshot)
        let categoryResolver = CategoryResolver(fileSystem: fileSystem)
        let catalogPresentation = CatalogPresentationService(catalog: catalog, resolver: categoryResolver)

        let engine = AerialEngine(
            catalog: catalog,
            picker: AssetPicker(),
            urlSelector: FakeURLSelector(url: URL(string: "https://example.com/any.mov")!),
            downloader: FakeDownloader(),
            brightnessStore: NoopBrightnessStore(),
            storeEditor: FakeStoreEditor(),
            reloader: FakeReloader(),
            stateStore: stateStore
        )

        let ui = await MainActor.run { AppUIState() }
        let settingsStore = await MainActor.run { [suiteName] in
            // `MainActor.run` takes a `@Sendable` closure; avoid capturing `UserDefaults` (non-Sendable).
            let defaultsForMainActor = UserDefaults(suiteName: suiteName)!
            return AppSettingsStore(userDefaults: defaultsForMainActor, initialSettings: AppSettings())
        }
        let notificationCoordinator = await MainActor.run {
            NotificationCoordinator(service: NoopNotificationPermissionService())
        }

        let rotationCoordinator = RotationCoordinator(
            stateStore: stateStore,
            engine: engine,
            initialSettings: AppSettings(),
            onDue: {}
        )
        let excludedCleaner = ExcludedAerialsCleaner(
            fileSystem: fileSystem,
            directoryDetector: ActiveVideoDirectoryDetector(runner: runner),
            catalog: catalog
        )
        let excludedCleanupCoordinator = ExcludedAerialsCleanupCoordinator(
            stateStore: FakeExcludedAerialsCleanupStateStore(),
            cleaner: excludedCleaner,
            initialSettings: AppSettings(),
            settingsProvider: { AppSettings() }
        )

        let actions = await MainActor.run {
            AppUserActions(
                ui: ui,
                settingsStore: settingsStore,
                stateStore: stateStore,
                rotationCoordinator: rotationCoordinator,
                excludedAerialsCleanupCoordinator: excludedCleanupCoordinator,
                catalogPresentation: catalogPresentation,
                screensaverLauncher: NoopScreensaverLauncher(),
                systemSettingsOpener: NoopSystemSettingsOpener(),
                notificationCoordinator: notificationCoordinator
            )
        }

        await actions.nextInSubcategory()

        let message = await MainActor.run { ui.lastErrorMessage }
        let status = await MainActor.run { ui.statusLine }

        #expect(message == "No current subcategory is available for the active Aerial.")
        #expect(status == "Error: No current subcategory is available for the active Aerial.")
    }
}

