import Foundation
import Testing

@testable import AerialFlow

struct AerialEngineTests {
    private actor StateStore: AerialEngineStateStore {
        private var lastAssetID: String?
        private var lastChange: Date?

        init(lastAssetID: String?, lastChange: Date? = nil) {
            self.lastAssetID = lastAssetID
            self.lastChange = lastChange
        }

        func getLastAssetID() async -> String? { lastAssetID }
        func setLastAssetID(_ id: String?) async { lastAssetID = id }
        func getLastChange() async -> Date? { lastChange }
        func setLastChange(_ date: Date?) async { lastChange = date }
    }

    private struct Settings: AerialEngineSettings {
        let excludedCategoryIDs: Set<String>
        let randomMode: Bool
        let qualityPreference: VideoQualityPreference
        let downloadTimeout: TimeInterval
        let indexPlistURL: URL
    }

    private enum TestError: Error {
        case catalogLoadFailed
    }

    private struct FakeCatalog: AerialCataloging {
        let snapshot: AerialCatalog.Snapshot
        func loadSnapshot() async throws -> AerialCatalog.Snapshot { snapshot }
    }

    private struct FailingCatalog: AerialCataloging {
        func loadSnapshot() async throws -> AerialCatalog.Snapshot {
            throw TestError.catalogLoadFailed
        }
    }

    /// Thread-safe event recorder for verifying operation ordering in tests.
    ///
    /// Uses `@unchecked Sendable` with `NSLock` because:
    /// - The protocols being tested (`AssetPicking`, `WallpaperApplying`, etc.) have synchronous methods
    /// - Swift `actor` requires async access, which would require changing production protocols
    /// - The NSLock provides correct synchronization for concurrent access
    ///
    /// This pattern is acceptable for test helpers where protocols constrain sync requirements.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _events: [String] = []

        func record(_ e: String) {
            lock.lock()
            _events.append(e)
            lock.unlock()
        }

        func snapshot() -> [String] {
            lock.lock()
            defer { lock.unlock() }
            return _events
        }
    }

    private struct FakePicker: AssetPicking {
        let recorder: Recorder
        func pickNext(
            assets: [AerialAsset],
            excludedCategoryIDs: Set<String>,
            currentAssetID: String?,
            randomMode: Bool,
            rng: inout some RandomNumberGenerator
        ) throws -> AerialAsset {
            _ = excludedCategoryIDs
            _ = currentAssetID
            _ = randomMode
            _ = rng
            recorder.record("pick")
            return assets.sorted(by: { $0.id < $1.id })[0]
        }
    }

    private struct FakeURLSelector: AssetURLSelecting {
        let recorder: Recorder
        let url: URL
        func pickURL(for asset: AerialAsset, preference: VideoQualityPreference) throws -> URL {
            _ = asset
            _ = preference
            recorder.record("url")
            return url
        }
    }

    private struct FakeDownloader: AssetDownloadEnsuring {
        let recorder: Recorder
        func ensureDownloaded(assetID: String, url: URL?, timeout: TimeInterval) async throws -> AssetDownloader.Result {
            _ = assetID
            _ = url
            _ = timeout
            recorder.record("download")
            return .init(destinationURL: URL(fileURLWithPath: "/tmp/ASSET.mov"), didDownload: true)
        }
    }

    private struct FakeStoreEditor: WallpaperApplying {
        let recorder: Recorder
        func applyAerialAssetID(_ assetID: String, indexPlistURL: URL) throws -> WallpaperStoreEditor.ApplyResult {
            _ = assetID
            _ = indexPlistURL
            recorder.record("apply")
            return .init(updatedProviderNodeCount: 2, backupURL: URL(fileURLWithPath: "/tmp/Index.plist.bak"))
        }
    }

    private struct FakeReloader: WallpaperReloading {
        let recorder: Recorder
        func reloadWallpaperPipelines() {
            recorder.record("reload")
        }
    }

    @Test func testNextRunsPickDownloadApplyReload_inOrder() async throws {
        let recorder = Recorder()
        let state = StateStore(lastAssetID: "b")

        let assets = [
            AerialAsset(id: "a", categories: [], urlVariants: ["url-4K": URL(string: "https://example.com/a.mov")!]),
            AerialAsset(id: "b", categories: [], urlVariants: ["url-4K": URL(string: "https://example.com/b.mov")!]),
        ]
        let catalogSnapshot = AerialCatalog.Snapshot(assets: assets, categories: [], fileURL: URL(fileURLWithPath: "/dev/null"), fileModificationDate: nil)

        let engine = AerialEngine(
            catalog: FakeCatalog(snapshot: catalogSnapshot),
            categoryResolver: CategoryResolver(fileSystem: InMemoryFileSystem(), bundleRootURL: URL(fileURLWithPath: "/Bundle", isDirectory: true)),
            picker: FakePicker(recorder: recorder),
            urlSelector: FakeURLSelector(recorder: recorder, url: URL(string: "https://example.com/a.mov")!),
            downloader: FakeDownloader(recorder: recorder),
            storeEditor: FakeStoreEditor(recorder: recorder),
            reloader: FakeReloader(recorder: recorder),
            settings: Settings(
                excludedCategoryIDs: [],
                randomMode: false,
                qualityPreference: .prefer4k,
                downloadTimeout: 5,
                indexPlistURL: URL(fileURLWithPath: "/Users/test/Index.plist")
            ),
            stateStore: state,
            now: { Date(timeIntervalSince1970: 1) }
        )

        _ = try await engine.next(manual: true)

        let events = recorder.snapshot()
        #expect(events == ["pick", "url", "download", "apply", "reload"])

        let lastAsset = await state.getLastAssetID()
        #expect(lastAsset == "a")
    }

    @Test func testNext_propagatesCatalogLoadFailure() async {
        let recorder = Recorder()
        let state = StateStore(lastAssetID: nil)

        let engine = AerialEngine(
            catalog: FailingCatalog(),
            categoryResolver: CategoryResolver(fileSystem: InMemoryFileSystem(), bundleRootURL: URL(fileURLWithPath: "/Bundle", isDirectory: true)),
            picker: FakePicker(recorder: recorder),
            urlSelector: FakeURLSelector(recorder: recorder, url: URL(string: "https://example.com/a.mov")!),
            downloader: FakeDownloader(recorder: recorder),
            storeEditor: FakeStoreEditor(recorder: recorder),
            reloader: FakeReloader(recorder: recorder),
            settings: Settings(
                excludedCategoryIDs: [],
                randomMode: false,
                qualityPreference: .prefer4k,
                downloadTimeout: 5,
                indexPlistURL: URL(fileURLWithPath: "/Users/test/Index.plist")
            ),
            stateStore: state,
            now: { Date(timeIntervalSince1970: 1) }
        )

        do {
            _ = try await engine.next(manual: true)
            #expect(Bool(false), "Expected catalog load failure to be thrown")
        } catch {
            // Expected: catalog failure propagates
            #expect(error is TestError)
        }

        // Verify no operations were attempted after catalog failure
        let events = recorder.snapshot()
        #expect(events.isEmpty)
    }
}


