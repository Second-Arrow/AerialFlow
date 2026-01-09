import Foundation
import Testing
import KeyboardShortcuts
@testable import AerialFlow

private func eventually(
    timeoutNanoseconds: UInt64,
    pollEveryNanoseconds: UInt64 = 20_000_000, // 20ms
    _ condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while DispatchTime.now().uptimeNanoseconds < deadline {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: pollEveryNanoseconds)
    }
    return await condition()
}

/// `HotkeyBinding` is `Sendable`, but this test fake has internal mutable state guarded by `NSLock`,
/// so we use `@unchecked Sendable` to silence strict Swift 6 Sendable checking.
private final class FakeHotkeyBinder: HotkeyBinding, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var registeredNames: [KeyboardShortcuts.Name] = []
    private var handlers: [KeyboardShortcuts.Name: @Sendable () -> Void] = [:]

    func onKeyUp(for name: KeyboardShortcuts.Name, action: @escaping @Sendable () -> Void) {
        lock.lock()
        registeredNames.append(name)
        handlers[name] = action
        lock.unlock()
    }

    func trigger(_ name: KeyboardShortcuts.Name) {
        lock.lock()
        let handler = handlers[name]
        lock.unlock()
        handler?()
    }
}

/// `ScreensaverLaunching` is `Sendable`, but this test fake has internal mutable state guarded by `NSLock`,
/// so we use `@unchecked Sendable` to silence strict Swift 6 Sendable checking.
private final class FakeScreensaverLauncher: ScreensaverLaunching, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var startCallCount: Int = 0

    func start() throws {
        lock.lock()
        startCallCount += 1
        lock.unlock()
    }
}

private struct FakeLaunchAtLoginManager: LaunchAtLoginManaging {
    func status() -> LaunchAtLoginStatus { .disabled }
    func register() throws {}
    func unregister() throws {}
}

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
            issues: [.indexPlistMissing]
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

struct AppStateHotkeyBindingTests {
    enum TestError: Error {
        case couldNotCreateUserDefaultsSuite
    }

    @Test func testInit_registersAllHotkeyHandlers() async throws {
        let suiteName = "AerialFlowTests.AppStateHotkeys.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.couldNotCreateUserDefaultsSuite
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let binder = FakeHotkeyBinder()
        let launcher = FakeScreensaverLauncher()

        let state = await MainActor.run { [suiteName] in
            // `MainActor.run` takes a `@Sendable` closure; avoid capturing `UserDefaults` (non-Sendable).
            let defaultsForMainActor = UserDefaults(suiteName: suiteName)!
            let dependencies = AppDependencies.live(
                userDefaults: defaultsForMainActor,
                screensaverLauncher: launcher,
                hotkeyBinder: binder
            )
            return AppState(dependencies: dependencies, userDefaults: defaultsForMainActor)
        }
        _ = state

        let names = Set(binder.registeredNames)
        #expect(names.contains(.nextAerial))
        #expect(names.contains(.nextInSubcategory))
        #expect(names.contains(.excludeCurrentSubcategoryAndNext))
        #expect(names.contains(.togglePause))
        #expect(names.contains(.goToScreensaver))
        #expect(names.count == 5)
    }

    @Test func testGoToScreensaverHotkey_invokesLauncher() async throws {
        let suiteName = "AerialFlowTests.AppStateGoToScreensaver.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.couldNotCreateUserDefaultsSuite
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let binder = FakeHotkeyBinder()
        let launcher = FakeScreensaverLauncher()

        let state = await MainActor.run { [suiteName] in
            // `MainActor.run` takes a `@Sendable` closure; avoid capturing `UserDefaults` (non-Sendable).
            let defaultsForMainActor = UserDefaults(suiteName: suiteName)!
            let dependencies = AppDependencies.live(
                userDefaults: defaultsForMainActor,
                screensaverLauncher: launcher,
                hotkeyBinder: binder
            )
            return AppState(dependencies: dependencies, userDefaults: defaultsForMainActor)
        }
        _ = state

        binder.trigger(.goToScreensaver)
        // The handler schedules work onto MainActor; wait briefly for it to run.
        let didStart = await eventually(timeoutNanoseconds: 2_000_000_000) {
            launcher.startCallCount == 1
        }
        #expect(didStart)
    }

    @Test func testExcludeCurrentSubcategoryAndNextHotkey_updatesExcludedAssetIDs_thenAdvances() async throws {
        let suiteName = "AerialFlowTests.AppStateExcludeCurrentAndNext.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.couldNotCreateUserDefaultsSuite
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let binder = FakeHotkeyBinder()
        let launcher = FakeScreensaverLauncher()

        let stateStore = FakeEngineStateStore(lastAssetID: "b")
        let assets = [
            AerialAsset(
                id: "b",
                categories: [],
                subcategories: ["sub1"],
                urlVariants: ["url-4K": URL(string: "https://example.com/b.mov")!]
            ),
            AerialAsset(
                id: "c",
                categories: [],
                subcategories: ["sub2"],
                urlVariants: ["url-4K": URL(string: "https://example.com/c.mov")!]
            ),
        ]
        let snapshot = AerialCatalog.Snapshot(
            assets: assets,
            categories: [],
            fileURL: URL(fileURLWithPath: "/dev/null"),
            fileModificationDate: nil
        )

        let fileSystem = InMemoryFileSystem()
        let runner = FakeCommandRunner()

        let engine = AerialEngine(
            catalog: FakeCatalog(snapshot: snapshot),
            picker: AssetPicker(),
            urlSelector: FakeURLSelector(url: URL(string: "https://example.com/any.mov")!),
            downloader: FakeDownloader(),
            brightnessStore: NoopBrightnessStore(),
            storeEditor: FakeStoreEditor(),
            reloader: FakeReloader(),
            stateStore: stateStore,
            now: { Date(timeIntervalSince1970: 1) }
        )

        let state = await MainActor.run { [suiteName] in
            // `MainActor.run` takes a `@Sendable` closure; avoid capturing `UserDefaults` (non-Sendable).
            let defaultsForMainActor = UserDefaults(suiteName: suiteName)!
            let dependencies = AppDependencies(
                fileSystem: fileSystem,
                commandRunner: runner,
                powerEventObserver: EmptyPowerEventObserver(),
                catalog: FakeCatalog(snapshot: snapshot),
                categoryResolver: CategoryResolver(fileSystem: fileSystem),
                stateStore: stateStore,
                excludedAerialsCleanupStateStore: FakeExcludedAerialsCleanupStateStore(),
                directoryDetector: ActiveVideoDirectoryDetector(runner: runner),
                downloader: FakeDownloader(),
                brightnessStore: NoopBrightnessStore(),
                storeEditor: WallpaperStoreEditor(fileSystem: fileSystem),
                reloader: FakeReloader(),
                excludedAerialsCleaner: ExcludedAerialsCleaner(
                    fileSystem: fileSystem,
                    directoryDetector: ActiveVideoDirectoryDetector(runner: runner),
                    catalog: FakeCatalog(snapshot: snapshot)
                ),
                screensaverLauncher: launcher,
                hotkeyBinder: binder,
                launchAtLoginManager: FakeLaunchAtLoginManager(),
                picker: AssetPicker(),
                urlSelector: AssetURLSelector(),
                engine: engine,
                updaterViewModel: UpdaterViewModel(controller: AutoUpdateManager(startingUpdater: false).controller),
                systemAccessProbe: SystemAccessProbe(
                    fileSystem: fileSystem,
                    directoryDetector: ActiveVideoDirectoryDetector(runner: runner),
                    storeEditor: WallpaperStoreEditor(fileSystem: fileSystem)
                ),
                notificationPermissionService: NoopNotificationPermissionService(),
                systemSettingsOpener: NoopSystemSettingsOpener()
            )
            return AppState(dependencies: dependencies, userDefaults: defaultsForMainActor)
        }
        _ = state

        binder.trigger(.excludeCurrentSubcategoryAndNext)

        // Wait for hotkey handler to run.
        let didExcludeB = await eventually(timeoutNanoseconds: 3_000_000_000) {
            await MainActor.run { state.settings.excludedAssetIDs.contains("b") }
        }
        #expect(didExcludeB)

        let didAdvance = await eventually(timeoutNanoseconds: 12_000_000_000) {
            await stateStore.getLastAssetID() == "c"
        }
        #expect(didAdvance)
    }

    @Test func testExcludeCurrentSubcategoryAndNextHotkey_revertsExclusionsOnNoEligibleAssets() async throws {
        let suiteName = "AerialFlowTests.AppStateExcludeCurrentAndNextReverts.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.couldNotCreateUserDefaultsSuite
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let binder = FakeHotkeyBinder()
        let launcher = FakeScreensaverLauncher()

        let stateStore = FakeEngineStateStore(lastAssetID: "b")
        let assets = [
            AerialAsset(
                id: "b",
                categories: [],
                subcategories: ["sub1"],
                urlVariants: ["url-4K": URL(string: "https://example.com/b.mov")!]
            ),
        ]
        let snapshot = AerialCatalog.Snapshot(
            assets: assets,
            categories: [],
            fileURL: URL(fileURLWithPath: "/dev/null"),
            fileModificationDate: nil
        )

        let fileSystem = InMemoryFileSystem()
        let runner = FakeCommandRunner()

        let engine = AerialEngine(
            catalog: FakeCatalog(snapshot: snapshot),
            picker: AssetPicker(),
            urlSelector: FakeURLSelector(url: URL(string: "https://example.com/any.mov")!),
            downloader: FakeDownloader(),
            brightnessStore: NoopBrightnessStore(),
            storeEditor: FakeStoreEditor(),
            reloader: FakeReloader(),
            stateStore: stateStore,
            now: { Date(timeIntervalSince1970: 1) }
        )

        let state = await MainActor.run { [suiteName] in
            // `MainActor.run` takes a `@Sendable` closure; avoid capturing `UserDefaults` (non-Sendable).
            let defaultsForMainActor = UserDefaults(suiteName: suiteName)!
            let dependencies = AppDependencies(
                fileSystem: fileSystem,
                commandRunner: runner,
                powerEventObserver: EmptyPowerEventObserver(),
                catalog: FakeCatalog(snapshot: snapshot),
                categoryResolver: CategoryResolver(fileSystem: fileSystem),
                stateStore: stateStore,
                excludedAerialsCleanupStateStore: FakeExcludedAerialsCleanupStateStore(),
                directoryDetector: ActiveVideoDirectoryDetector(runner: runner),
                downloader: FakeDownloader(),
                brightnessStore: NoopBrightnessStore(),
                storeEditor: WallpaperStoreEditor(fileSystem: fileSystem),
                reloader: FakeReloader(),
                excludedAerialsCleaner: ExcludedAerialsCleaner(
                    fileSystem: fileSystem,
                    directoryDetector: ActiveVideoDirectoryDetector(runner: runner),
                    catalog: FakeCatalog(snapshot: snapshot)
                ),
                screensaverLauncher: launcher,
                hotkeyBinder: binder,
                launchAtLoginManager: FakeLaunchAtLoginManager(),
                picker: AssetPicker(),
                urlSelector: AssetURLSelector(),
                engine: engine,
                updaterViewModel: UpdaterViewModel(controller: AutoUpdateManager(startingUpdater: false).controller),
                systemAccessProbe: SystemAccessProbe(
                    fileSystem: fileSystem,
                    directoryDetector: ActiveVideoDirectoryDetector(runner: runner),
                    storeEditor: WallpaperStoreEditor(fileSystem: fileSystem)
                ),
                notificationPermissionService: NoopNotificationPermissionService(),
                systemSettingsOpener: NoopSystemSettingsOpener()
            )
            return AppState(dependencies: dependencies, userDefaults: defaultsForMainActor)
        }
        _ = state

        // Seed an existing exclusion that must be preserved.
        await MainActor.run {
            state.settings.excludedAssetIDs = ["keep"]
        }

        binder.trigger(.excludeCurrentSubcategoryAndNext)

        // Wait for the handler to complete (it should fail due to no eligible assets and revert).
        let didError = await eventually(timeoutNanoseconds: 6_000_000_000) {
            let status = await MainActor.run { state.statusLine }
            return status.hasPrefix("Error:")
        }
        #expect(didError)

        let current = await MainActor.run { state.settings.excludedAssetIDs }
        #expect(current == ["keep"])
    }

    @Test func testNextInSubcategoryHotkey_advancesWithinPrimarySubcategory() async throws {
        let suiteName = "AerialFlowTests.AppStateNextInSubcategory.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.couldNotCreateUserDefaultsSuite
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let binder = FakeHotkeyBinder()
        let launcher = FakeScreensaverLauncher()

        let stateStore = FakeEngineStateStore(lastAssetID: "b")
        let assets = [
            AerialAsset(
                id: "a",
                categories: [],
                subcategories: ["sub1"],
                urlVariants: ["url-4K": URL(string: "https://example.com/a.mov")!]
            ),
            AerialAsset(
                id: "b",
                categories: [],
                subcategories: ["sub2", "sub1"],
                urlVariants: ["url-4K": URL(string: "https://example.com/b.mov")!]
            ),
            AerialAsset(
                id: "c",
                categories: [],
                subcategories: ["sub1"],
                urlVariants: ["url-4K": URL(string: "https://example.com/c.mov")!]
            ),
            AerialAsset(
                id: "z",
                categories: [],
                subcategories: ["sub2"],
                urlVariants: ["url-4K": URL(string: "https://example.com/z.mov")!]
            ),
        ]
        let snapshot = AerialCatalog.Snapshot(
            assets: assets,
            categories: [],
            fileURL: URL(fileURLWithPath: "/dev/null"),
            fileModificationDate: nil
        )

        let fileSystem = InMemoryFileSystem()
        let runner = FakeCommandRunner()

        let engine = AerialEngine(
            catalog: FakeCatalog(snapshot: snapshot),
            picker: AssetPicker(),
            urlSelector: FakeURLSelector(url: URL(string: "https://example.com/any.mov")!),
            downloader: FakeDownloader(),
            brightnessStore: NoopBrightnessStore(),
            storeEditor: FakeStoreEditor(),
            reloader: FakeReloader(),
            stateStore: stateStore,
            now: { Date(timeIntervalSince1970: 1) }
        )

        let state = await MainActor.run { [suiteName] in
            let defaultsForMainActor = UserDefaults(suiteName: suiteName)!
            let dependencies = AppDependencies(
                fileSystem: fileSystem,
                commandRunner: runner,
                powerEventObserver: EmptyPowerEventObserver(),
                catalog: FakeCatalog(snapshot: snapshot),
                categoryResolver: CategoryResolver(fileSystem: fileSystem),
                stateStore: stateStore,
                excludedAerialsCleanupStateStore: FakeExcludedAerialsCleanupStateStore(),
                directoryDetector: ActiveVideoDirectoryDetector(runner: runner),
                downloader: FakeDownloader(),
                brightnessStore: NoopBrightnessStore(),
                storeEditor: WallpaperStoreEditor(fileSystem: fileSystem),
                reloader: FakeReloader(),
                excludedAerialsCleaner: ExcludedAerialsCleaner(
                    fileSystem: fileSystem,
                    directoryDetector: ActiveVideoDirectoryDetector(runner: runner),
                    catalog: FakeCatalog(snapshot: snapshot)
                ),
                screensaverLauncher: launcher,
                hotkeyBinder: binder,
                launchAtLoginManager: FakeLaunchAtLoginManager(),
                picker: AssetPicker(),
                urlSelector: AssetURLSelector(),
                engine: engine,
                updaterViewModel: UpdaterViewModel(controller: AutoUpdateManager(startingUpdater: false).controller),
                systemAccessProbe: SystemAccessProbe(
                    fileSystem: fileSystem,
                    directoryDetector: ActiveVideoDirectoryDetector(runner: runner),
                    storeEditor: WallpaperStoreEditor(fileSystem: fileSystem)
                ),
                notificationPermissionService: NoopNotificationPermissionService(),
                systemSettingsOpener: NoopSystemSettingsOpener()
            )
            return AppState(dependencies: dependencies, userDefaults: defaultsForMainActor)
        }
        _ = state

        binder.trigger(.nextInSubcategory)

        let didAdvance = await eventually(timeoutNanoseconds: 12_000_000_000) {
            await stateStore.getLastAssetID() == "c"
        }
        #expect(didAdvance)
    }

    @Test func testNextInSubcategoryHotkey_noSubcategory_setsErrorAndDoesNotAdvance() async throws {
        let suiteName = "AerialFlowTests.AppStateNextInSubcategoryNoSub.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.couldNotCreateUserDefaultsSuite
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let binder = FakeHotkeyBinder()
        let launcher = FakeScreensaverLauncher()

        let stateStore = FakeEngineStateStore(lastAssetID: "b")
        let assets = [
            AerialAsset(
                id: "b",
                categories: [],
                subcategories: [],
                urlVariants: ["url-4K": URL(string: "https://example.com/b.mov")!]
            ),
            AerialAsset(
                id: "c",
                categories: [],
                subcategories: ["sub1"],
                urlVariants: ["url-4K": URL(string: "https://example.com/c.mov")!]
            ),
        ]
        let snapshot = AerialCatalog.Snapshot(
            assets: assets,
            categories: [],
            fileURL: URL(fileURLWithPath: "/dev/null"),
            fileModificationDate: nil
        )

        let fileSystem = InMemoryFileSystem()
        let runner = FakeCommandRunner()

        let engine = AerialEngine(
            catalog: FakeCatalog(snapshot: snapshot),
            picker: AssetPicker(),
            urlSelector: FakeURLSelector(url: URL(string: "https://example.com/any.mov")!),
            downloader: FakeDownloader(),
            brightnessStore: NoopBrightnessStore(),
            storeEditor: FakeStoreEditor(),
            reloader: FakeReloader(),
            stateStore: stateStore,
            now: { Date(timeIntervalSince1970: 1) }
        )

        let state = await MainActor.run { [suiteName] in
            let defaultsForMainActor = UserDefaults(suiteName: suiteName)!
            let dependencies = AppDependencies(
                fileSystem: fileSystem,
                commandRunner: runner,
                powerEventObserver: EmptyPowerEventObserver(),
                catalog: FakeCatalog(snapshot: snapshot),
                categoryResolver: CategoryResolver(fileSystem: fileSystem),
                stateStore: stateStore,
                excludedAerialsCleanupStateStore: FakeExcludedAerialsCleanupStateStore(),
                directoryDetector: ActiveVideoDirectoryDetector(runner: runner),
                downloader: FakeDownloader(),
                brightnessStore: NoopBrightnessStore(),
                storeEditor: WallpaperStoreEditor(fileSystem: fileSystem),
                reloader: FakeReloader(),
                excludedAerialsCleaner: ExcludedAerialsCleaner(
                    fileSystem: fileSystem,
                    directoryDetector: ActiveVideoDirectoryDetector(runner: runner),
                    catalog: FakeCatalog(snapshot: snapshot)
                ),
                screensaverLauncher: launcher,
                hotkeyBinder: binder,
                launchAtLoginManager: FakeLaunchAtLoginManager(),
                picker: AssetPicker(),
                urlSelector: AssetURLSelector(),
                engine: engine,
                updaterViewModel: UpdaterViewModel(controller: AutoUpdateManager(startingUpdater: false).controller),
                systemAccessProbe: SystemAccessProbe(
                    fileSystem: fileSystem,
                    directoryDetector: ActiveVideoDirectoryDetector(runner: runner),
                    storeEditor: WallpaperStoreEditor(fileSystem: fileSystem)
                ),
                notificationPermissionService: NoopNotificationPermissionService(),
                systemSettingsOpener: NoopSystemSettingsOpener()
            )
            return AppState(dependencies: dependencies, userDefaults: defaultsForMainActor)
        }
        _ = state

        binder.trigger(.nextInSubcategory)

        for _ in 0..<200 {
            let status = await MainActor.run { state.statusLine }
            if status.hasPrefix("Error:") { break }
            try? await Task.sleep(nanoseconds: 2_000_000) // 2ms
        }

        let status = await MainActor.run { state.statusLine }
        #expect(status.hasPrefix("Error:"))

        let lastAsset = await stateStore.getLastAssetID()
        #expect(lastAsset == "b")
    }
}


