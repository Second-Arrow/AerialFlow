import Foundation
import Testing
import KeyboardShortcuts
@testable import AerialFlow

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

private struct FakeTipJarPurchaser: TipJarPurchasing {
    func fetchProducts(productIDs: [String]) async throws -> [TipJarProduct] { [] }
    func purchase(productID: String) async -> TipJarPurchaseOutcome { .userCancelled }
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
        #expect(names.contains(.excludeCurrentSubcategoryAndNext))
        #expect(names.contains(.togglePause))
        #expect(names.contains(.goToScreensaver))
        #expect(names.count == 4)
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
        for _ in 0..<50 {
            if launcher.startCallCount == 1 { break }
            try? await Task.sleep(nanoseconds: 2_000_000) // 2ms
        }

        #expect(launcher.startCallCount == 1)
    }

    @Test func testExcludeCurrentSubcategoryAndNextHotkey_updatesExcludedSubcategoryIDs_thenAdvances() async throws {
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
                catalog: FakeCatalog(snapshot: snapshot),
                categoryResolver: CategoryResolver(fileSystem: fileSystem),
                stateStore: stateStore,
                directoryDetector: ActiveVideoDirectoryDetector(runner: runner),
                downloader: FakeDownloader(),
                storeEditor: WallpaperStoreEditor(fileSystem: fileSystem),
                reloader: FakeReloader(),
                runGuard: NeverRunGuard(),
                screensaverLauncher: launcher,
                hotkeyBinder: binder,
                launchAtLoginManager: FakeLaunchAtLoginManager(),
                picker: AssetPicker(),
                urlSelector: AssetURLSelector(),
                engine: engine,
                tipJarPurchaser: FakeTipJarPurchaser()
            )
            return AppState(dependencies: dependencies, userDefaults: defaultsForMainActor)
        }
        _ = state

        binder.trigger(.excludeCurrentSubcategoryAndNext)

        // Wait for hotkey handler to run.
        for _ in 0..<200 {
            let hasSub1 = await MainActor.run { state.settings.excludedSubcategoryIDs.contains("sub1") }
            if hasSub1 { break }
            try? await Task.sleep(nanoseconds: 2_000_000) // 2ms
        }

        let hasSub1 = await MainActor.run { state.settings.excludedSubcategoryIDs.contains("sub1") }
        #expect(hasSub1)

        for _ in 0..<200 {
            let status = await MainActor.run { state.statusLine }
            if status == "c" { break }
            try? await Task.sleep(nanoseconds: 2_000_000) // 2ms
        }

        let status = await MainActor.run { state.statusLine }
        #expect(status == "c")
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
                catalog: FakeCatalog(snapshot: snapshot),
                categoryResolver: CategoryResolver(fileSystem: fileSystem),
                stateStore: stateStore,
                directoryDetector: ActiveVideoDirectoryDetector(runner: runner),
                downloader: FakeDownloader(),
                storeEditor: WallpaperStoreEditor(fileSystem: fileSystem),
                reloader: FakeReloader(),
                runGuard: NeverRunGuard(),
                screensaverLauncher: launcher,
                hotkeyBinder: binder,
                launchAtLoginManager: FakeLaunchAtLoginManager(),
                picker: AssetPicker(),
                urlSelector: AssetURLSelector(),
                engine: engine,
                tipJarPurchaser: FakeTipJarPurchaser()
            )
            return AppState(dependencies: dependencies, userDefaults: defaultsForMainActor)
        }
        _ = state

        // Seed an existing exclusion that must be preserved.
        await MainActor.run {
            state.settings.excludedSubcategoryIDs = ["keep"]
        }

        binder.trigger(.excludeCurrentSubcategoryAndNext)

        // Wait for the handler to attempt and then revert.
        for _ in 0..<200 {
            let current = await MainActor.run { state.settings.excludedSubcategoryIDs }
            if current == ["keep"] { break }
            try? await Task.sleep(nanoseconds: 2_000_000) // 2ms
        }

        let current = await MainActor.run { state.settings.excludedSubcategoryIDs }
        #expect(current == ["keep"])
    }
}


