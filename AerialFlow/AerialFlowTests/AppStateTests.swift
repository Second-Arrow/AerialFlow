//
//  AppStateTests.swift
//  AerialFlowTests
//
//  Created by Floris Robbemont on 02/01/2026.
//

import Testing
import Foundation
import KeyboardShortcuts
@testable import AerialFlow

private struct FakeLaunchAtLoginManager: LaunchAtLoginManaging {
    func status() -> LaunchAtLoginStatus { .disabled }
    func register() throws {}
    func unregister() throws {}
}

private struct FakeCatalog: AerialCataloging {
    let snapshot: AerialCatalog.Snapshot
    func loadSnapshot() async throws -> AerialCatalog.Snapshot { snapshot }
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

private struct NoopScreensaverLauncher: ScreensaverLaunching {
    func start() throws {}
}

private struct NoopHotkeyBinder: HotkeyBinding {
    func onKeyUp(for name: KeyboardShortcuts.Name, action: @escaping @Sendable () -> Void) {
        _ = name
        _ = action
    }
}

struct AppStateTests {
    enum TestError: Error {
        case couldNotCreateUserDefaultsSuite
    }

    @Test func testTogglePaused_flipsState() async throws {
        let suiteName = "AerialFlowTests.AppState.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.couldNotCreateUserDefaultsSuite
        }

        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = await MainActor.run { [suiteName] in
            // `MainActor.run` takes a `@Sendable` closure; avoid capturing `UserDefaults` (non-Sendable).
            let defaultsForMainActor = UserDefaults(suiteName: suiteName)!
            let dependencies = AppDependencies.live(userDefaults: defaultsForMainActor)
            return AppState(dependencies: dependencies, userDefaults: defaultsForMainActor)
        }
        let initial = await MainActor.run { state.isPaused }

        await MainActor.run { state.setRotationEnabled(state.isPaused) }
        let toggled = await MainActor.run { state.isPaused }

        #expect(toggled != initial)
    }

    @Test func testTogglePaused_twice_returnsToOriginal() async throws {
        let suiteName = "AerialFlowTests.AppState.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.couldNotCreateUserDefaultsSuite
        }

        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = await MainActor.run { [suiteName] in
            // `MainActor.run` takes a `@Sendable` closure; avoid capturing `UserDefaults` (non-Sendable).
            let defaultsForMainActor = UserDefaults(suiteName: suiteName)!
            let dependencies = AppDependencies.live(userDefaults: defaultsForMainActor)
            return AppState(dependencies: dependencies, userDefaults: defaultsForMainActor)
        }
        let initial = await MainActor.run { state.isPaused }

        await MainActor.run {
            state.setRotationEnabled(state.isPaused)
            state.setRotationEnabled(state.isPaused)
        }
        let final = await MainActor.run { state.isPaused }

        #expect(final == initial)
    }

    @Test func testSelectedSettingsDestination_defaultsToGeneral_andCanChange() async throws {
        let suiteName = "AerialFlowTests.AppState.SettingsDestination.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.couldNotCreateUserDefaultsSuite
        }

        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = await MainActor.run { [suiteName] in
            // `MainActor.run` takes a `@Sendable` closure; avoid capturing `UserDefaults` (non-Sendable).
            let defaultsForMainActor = UserDefaults(suiteName: suiteName)!
            let dependencies = AppDependencies.live(userDefaults: defaultsForMainActor)
            return AppState(dependencies: dependencies, userDefaults: defaultsForMainActor)
        }

        let initial = await MainActor.run { state.selectedSettingsDestination }
        #expect(initial == .general)

        await MainActor.run { state.selectedSettingsDestination = .about }
        let updated = await MainActor.run { state.selectedSettingsDestination }
        #expect(updated == .about)
    }

    @Test func testPowerEvents_willSleepThenDidWake_hibernatesAndResumesAccordingToSettings() async throws {
        let suiteName = "AerialFlowTests.AppState.PowerEvents.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.couldNotCreateUserDefaultsSuite
        }

        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var settings = AppSettings()
        settings.isRotationEnabled = true
        settings.rotationIntervalSeconds = 3_600
        settings.sleepResumeBehavior = .immediatelyGoToNextAerial
        settings.save(to: defaults)

        let stateStore = FakeEngineStateStore(lastAssetID: nil, lastChange: Date())
        let assets = [
            AerialAsset(
                id: "a",
                categories: [],
                subcategories: [],
                urlVariants: ["url-4K": URL(string: "https://example.com/a.mov")!]
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
            urlSelector: AssetURLSelector(),
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
                powerEventObserver: SequencePowerEventObserver(eventsToEmit: [.willSleep, .didWake]),
                catalog: FakeCatalog(snapshot: snapshot),
                categoryResolver: CategoryResolver(fileSystem: fileSystem),
                stateStore: stateStore,
                excludedAerialsCleanupStateStore: FakeExcludedAerialsCleanupStateStore(),
                directoryDetector: ActiveVideoDirectoryDetector(runner: runner),
                features: AerialFlowFeatures(movDownloadMode: .directToVideoDirectory),
                downloader: FakeDownloader(),
                brightnessStore: NoopBrightnessStore(),
                storeEditor: WallpaperStoreEditor(fileSystem: fileSystem),
                reloader: FakeReloader(),
                excludedAerialsCleaner: ExcludedAerialsCleaner(
                    fileSystem: fileSystem,
                    directoryDetector: ActiveVideoDirectoryDetector(runner: runner),
                    catalog: FakeCatalog(snapshot: snapshot),
                    features: AerialFlowFeatures(movDownloadMode: .directToVideoDirectory)
                ),
                screensaverLauncher: NoopScreensaverLauncher(),
                hotkeyBinder: NoopHotkeyBinder(),
                launchAtLoginManager: FakeLaunchAtLoginManager(),
                picker: AssetPicker(),
                urlSelector: AssetURLSelector(),
                engine: engine,
                updaterViewModel: UpdaterViewModel(controller: AutoUpdateManager(startingUpdater: false).controller),
                systemAccessProbe: SystemAccessProbe(
                    fileSystem: fileSystem,
                    directoryDetector: ActiveVideoDirectoryDetector(runner: runner),
                    storeEditor: WallpaperStoreEditor(fileSystem: fileSystem),
                    features: AerialFlowFeatures(movDownloadMode: .directToVideoDirectory)
                ),
                notificationPermissionService: NoopNotificationPermissionService(),
                systemSettingsOpener: NoopSystemSettingsOpener()
            )
            return AppState(dependencies: dependencies, userDefaults: defaultsForMainActor)
        }
        _ = state

        // Wait for power event observation to deliver didWake and for the immediate rotation to complete.
        for _ in 0..<200 {
            if await stateStore.getLastAssetID() == "a" { break }
            try? await Task.sleep(nanoseconds: 2_000_000) // 2ms
        }

        #expect(await stateStore.getLastAssetID() == "a")
    }

    @Test func testCalculateStorageUsed_emptyDirectory_returnsZero() throws {
        let fileSystem = InMemoryFileSystem()
        let videoDir = URL(fileURLWithPath: "/test/videos")
        try fileSystem.createDirectory(at: videoDir)

        let result = DiagnosticsSnapshotLoader.calculateStorageUsed(fileSystem: fileSystem, videoDirectory: videoDir)
        #expect(result == 0)
    }

    @Test func testCalculateStorageUsed_multipleMovFiles_sumsCorrectly() throws {
        let fileSystem = InMemoryFileSystem()
        let videoDir = URL(fileURLWithPath: "/test/videos")
        try fileSystem.createDirectory(at: videoDir)

        // Create multiple .mov files with different sizes
        let file1 = videoDir.appendingPathComponent("asset1.mov")
        let file2 = videoDir.appendingPathComponent("asset2.mov")
        let file3 = videoDir.appendingPathComponent("asset3.mov")

        let data1 = Data(repeating: 0, count: 1000)
        let data2 = Data(repeating: 0, count: 2000)
        let data3 = Data(repeating: 0, count: 3000)

        try fileSystem.writeData(data1, to: file1, options: [])
        try fileSystem.writeData(data2, to: file2, options: [])
        try fileSystem.writeData(data3, to: file3, options: [])

        let result = DiagnosticsSnapshotLoader.calculateStorageUsed(fileSystem: fileSystem, videoDirectory: videoDir)
        #expect(result == 6000) // 1000 + 2000 + 3000
    }

    @Test func testCalculateStorageUsed_directoryDoesNotExist_returnsNil() throws {
        let fileSystem = InMemoryFileSystem()
        let videoDir = URL(fileURLWithPath: "/test/videos")
        // Don't create the directory

        let result = DiagnosticsSnapshotLoader.calculateStorageUsed(fileSystem: fileSystem, videoDirectory: videoDir)
        #expect(result == nil)
    }

    @Test func testCalculateStorageUsed_excludesPartFiles() throws {
        let fileSystem = InMemoryFileSystem()
        let videoDir = URL(fileURLWithPath: "/test/videos")
        try fileSystem.createDirectory(at: videoDir)

        // Create a .mov file and a .part file
        let movFile = videoDir.appendingPathComponent("asset1.mov")
        let partFile = videoDir.appendingPathComponent(".asset2.mov.part")

        let movData = Data(repeating: 0, count: 1000)
        let partData = Data(repeating: 0, count: 5000)

        try fileSystem.writeData(movData, to: movFile, options: [])
        try fileSystem.writeData(partData, to: partFile, options: [])

        let result = DiagnosticsSnapshotLoader.calculateStorageUsed(fileSystem: fileSystem, videoDirectory: videoDir)
        // Should only count the .mov file, not the .part file
        #expect(result == 1000)
    }

    @Test func testCalculateStorageUsed_excludesHiddenMovFiles() throws {
        let fileSystem = InMemoryFileSystem()
        let videoDir = URL(fileURLWithPath: "/test/videos")
        try fileSystem.createDirectory(at: videoDir)

        // Create a regular .mov file and a hidden .mov file (starting with .)
        let movFile = videoDir.appendingPathComponent("asset1.mov")
        let hiddenMovFile = videoDir.appendingPathComponent(".asset2.mov")

        let movData = Data(repeating: 0, count: 1000)
        let hiddenData = Data(repeating: 0, count: 5000)

        try fileSystem.writeData(movData, to: movFile, options: [])
        try fileSystem.writeData(hiddenData, to: hiddenMovFile, options: [])

        let result = DiagnosticsSnapshotLoader.calculateStorageUsed(fileSystem: fileSystem, videoDirectory: videoDir)
        // Should only count the non-hidden .mov file
        #expect(result == 1000)
    }
}

