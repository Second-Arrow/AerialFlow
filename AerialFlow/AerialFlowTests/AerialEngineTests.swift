import Foundation
import Testing

@testable import AerialFlow

struct AerialEngineTests {
    private struct Settings: AerialEngineSettings {
        let excludedCategoryIDs: Set<String>
        let excludedSubcategoryIDs: Set<String>
        let excludedAssetIDs: Set<String>
        let randomMode: Bool
        let downloadTimeout: TimeInterval
        let indexPlistURL: URL
        let backupRetentionCount: Int
        let isLightSensitiveFilteringEnabled: Bool
        let allowedLightStartMinutes: Int
        let allowedLightEndMinutes: Int
        let lightSensitivity: Double
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
            excludedSubcategoryIDs: Set<String>,
            excludedAssetIDs: Set<String>,
            currentAssetID: String?,
            randomMode: Bool,
            rng: inout some RandomNumberGenerator
        ) throws -> AerialAsset {
            _ = excludedCategoryIDs
            _ = excludedSubcategoryIDs
            _ = excludedAssetIDs
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
        func pickURL(for asset: AerialAsset) throws -> URL {
            _ = asset
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
        func applyAerialAssetID(_ assetID: String, indexPlistURL: URL, backupRetentionCount: Int) throws -> WallpaperStoreEditor.ApplyResult {
            _ = assetID
            _ = indexPlistURL
            _ = backupRetentionCount
            recorder.record("apply")
            return .init(updatedProviderNodeCount: 2, backupURL: URL(fileURLWithPath: "/tmp/Index.plist.bak"))
        }

        func inspectAerialConfiguration(indexPlistURL: URL) throws -> WallpaperStoreEditor.AerialConfigurationStatus {
            _ = indexPlistURL
            return .init(
                totalProviderNodes: 2,
                desktopProviderNodes: 1,
                idleProviderNodes: 1,
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
            recorder.record("repair")
            return .init(didUpsertProviderNodes: false, updatedProviderNodeCount: 0, backupURL: URL(fileURLWithPath: "/tmp/Index.plist.bak"))
        }
    }

    private struct FakeReloader: WallpaperReloading {
        let recorder: Recorder
        func reloadWallpaperPipelines() {
            recorder.record("reload")
        }
    }

    private final class RepairingStoreEditor: WallpaperApplying, @unchecked Sendable {
        private let recorder: Recorder
        private let lock = NSLock()
        private var applyCount: Int = 0

        init(recorder: Recorder) {
            self.recorder = recorder
        }

        func applyAerialAssetID(_ assetID: String, indexPlistURL: URL, backupRetentionCount: Int) throws -> WallpaperStoreEditor.ApplyResult {
            _ = assetID
            _ = indexPlistURL
            _ = backupRetentionCount

            lock.lock()
            applyCount += 1
            let isFirst = (applyCount == 1)
            lock.unlock()

            recorder.record("apply")
            if isFirst {
                throw WallpaperStoreEditor.EditorError.noProviderNodesFound(provider: "com.apple.wallpaper.choice.aerials")
            }

            return .init(updatedProviderNodeCount: 2, backupURL: URL(fileURLWithPath: "/tmp/Index.plist.bak"))
        }

        func inspectAerialConfiguration(indexPlistURL: URL) throws -> WallpaperStoreEditor.AerialConfigurationStatus {
            _ = indexPlistURL
            return .init(totalProviderNodes: 0, desktopProviderNodes: 0, idleProviderNodes: 0, issues: [.noAerialProviderNodes])
        }

        func repairAerialConfiguration(
            desiredAssetID: String,
            indexPlistURL: URL,
            backupRetentionCount: Int
        ) throws -> WallpaperStoreEditor.AerialConfigurationRepairReport {
            _ = desiredAssetID
            _ = indexPlistURL
            _ = backupRetentionCount
            recorder.record("repair")
            return .init(didUpsertProviderNodes: true, updatedProviderNodeCount: 2, backupURL: URL(fileURLWithPath: "/tmp/Index.plist.bak"))
        }
    }

    @Test func testNext_outsideAllowedWindow_filtersToDarkAssets_whenBrightnessKnown() async throws {
        let recorder = Recorder()
        let state = FakeEngineStateStore(lastAssetID: nil)

        let assets = [
            AerialAsset(id: "bright", categories: [], urlVariants: ["url-4K": URL(string: "https://example.com/bright.mov")!]),
            AerialAsset(id: "dark", categories: [], urlVariants: ["url-4K": URL(string: "https://example.com/dark.mov")!]),
        ]
        let snapshot = AerialCatalog.Snapshot(assets: assets, categories: [], fileURL: URL(fileURLWithPath: "/dev/null"), fileModificationDate: nil)

        // Use a local-time date to avoid time zone offsets in Date(timeIntervalSince1970:).
        // 01:00 local is outside the default 10:00-18:00 range.
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 1
        comps.minute = 0
        comps.second = 0
        let morning = Calendar.current.date(from: comps) ?? Date()
        let engine = AerialEngine(
            catalog: FakeCatalog(snapshot: snapshot),
            picker: AssetPicker(),
            urlSelector: FakeURLSelector(recorder: recorder, url: URL(string: "https://example.com/dark.mov")!),
            downloader: FakeDownloader(recorder: recorder),
            brightnessStore: FixedDarknessBrightnessStore(darkAssetIDs: ["dark"]),
            storeEditor: FakeStoreEditor(recorder: recorder),
            reloader: FakeReloader(recorder: recorder),
            stateStore: state,
            now: { morning }
        )

        let report = try await engine.next(
            settings: Settings(
                excludedCategoryIDs: [],
                excludedSubcategoryIDs: [],
                excludedAssetIDs: [],
                randomMode: false,
                downloadTimeout: 5,
                indexPlistURL: URL(fileURLWithPath: "/Users/test/Index.plist"),
                backupRetentionCount: 10,
                isLightSensitiveFilteringEnabled: true,
                allowedLightStartMinutes: 10 * 60,
                allowedLightEndMinutes: 18 * 60,
                lightSensitivity: 0.5
            )
        )

        #expect(report.chosenAssetID == "dark")
    }

    @Test func testNext_outsideAllowedWindow_fallsBack_whenBrightnessUnknown() async throws {
        let recorder = Recorder()
        let state = FakeEngineStateStore(lastAssetID: nil)

        let assets = [
            AerialAsset(id: "a", categories: [], urlVariants: ["url-4K": URL(string: "https://example.com/a.mov")!]),
            AerialAsset(id: "b", categories: [], urlVariants: ["url-4K": URL(string: "https://example.com/b.mov")!]),
        ]
        let snapshot = AerialCatalog.Snapshot(assets: assets, categories: [], fileURL: URL(fileURLWithPath: "/dev/null"), fileModificationDate: nil)

        let morning = Date(timeIntervalSince1970: 9 * 60 * 60)
        let engine = AerialEngine(
            catalog: FakeCatalog(snapshot: snapshot),
            picker: AssetPicker(),
            urlSelector: FakeURLSelector(recorder: recorder, url: URL(string: "https://example.com/a.mov")!),
            downloader: FakeDownloader(recorder: recorder),
            brightnessStore: FixedDarknessBrightnessStore(darkAssetIDs: [], unknownAssetIDs: ["a", "b"]),
            storeEditor: FakeStoreEditor(recorder: recorder),
            reloader: FakeReloader(recorder: recorder),
            stateStore: state,
            now: { morning }
        )

        let report = try await engine.next(
            settings: Settings(
                excludedCategoryIDs: [],
                excludedSubcategoryIDs: [],
                excludedAssetIDs: [],
                randomMode: false,
                downloadTimeout: 5,
                indexPlistURL: URL(fileURLWithPath: "/Users/test/Index.plist"),
                backupRetentionCount: 10,
                isLightSensitiveFilteringEnabled: true,
                allowedLightStartMinutes: 10 * 60,
                allowedLightEndMinutes: 18 * 60,
                lightSensitivity: 0.5
            )
        )

        // Falls back to unfiltered assets; deterministic AssetPicker picks first when current nil.
        #expect(report.chosenAssetID == "a")
    }

    @Test func testNextRunsPickDownloadApplyReload_inOrder() async throws {
        let recorder = Recorder()
        let state = FakeEngineStateStore(lastAssetID: "b")

        let assets = [
            AerialAsset(id: "a", categories: [], urlVariants: ["url-4K": URL(string: "https://example.com/a.mov")!]),
            AerialAsset(id: "b", categories: [], urlVariants: ["url-4K": URL(string: "https://example.com/b.mov")!]),
        ]
        let catalogSnapshot = AerialCatalog.Snapshot(assets: assets, categories: [], fileURL: URL(fileURLWithPath: "/dev/null"), fileModificationDate: nil)

        let engine = AerialEngine(
            catalog: FakeCatalog(snapshot: catalogSnapshot),
            picker: FakePicker(recorder: recorder),
            urlSelector: FakeURLSelector(recorder: recorder, url: URL(string: "https://example.com/a.mov")!),
            downloader: FakeDownloader(recorder: recorder),
            brightnessStore: NoopBrightnessStore(),
            storeEditor: FakeStoreEditor(recorder: recorder),
            reloader: FakeReloader(recorder: recorder),
            stateStore: state,
            now: { Date(timeIntervalSince1970: 1) }
        )

        _ = try await engine.next(
            settings: Settings(
                excludedCategoryIDs: [],
                excludedSubcategoryIDs: [],
                excludedAssetIDs: [],
                randomMode: false,
                downloadTimeout: 5,
                indexPlistURL: URL(fileURLWithPath: "/Users/test/Index.plist"),
                backupRetentionCount: 10,
                isLightSensitiveFilteringEnabled: false,
                allowedLightStartMinutes: 10 * 60,
                allowedLightEndMinutes: 18 * 60,
                lightSensitivity: 0.5
            )
        )

        let events = recorder.snapshot()
        #expect(events == ["pick", "url", "download", "apply", "reload"])

        let lastAsset = await state.getLastAssetID()
        #expect(lastAsset == "a")
    }

    @Test func testNext_repairsThenApplies_whenProviderNodesMissing() async throws {
        let recorder = Recorder()
        let state = FakeEngineStateStore(lastAssetID: "b")

        let assets = [
            AerialAsset(id: "a", categories: [], urlVariants: ["url-4K": URL(string: "https://example.com/a.mov")!]),
            AerialAsset(id: "b", categories: [], urlVariants: ["url-4K": URL(string: "https://example.com/b.mov")!]),
        ]
        let catalogSnapshot = AerialCatalog.Snapshot(assets: assets, categories: [], fileURL: URL(fileURLWithPath: "/dev/null"), fileModificationDate: nil)

        let engine = AerialEngine(
            catalog: FakeCatalog(snapshot: catalogSnapshot),
            picker: FakePicker(recorder: recorder),
            urlSelector: FakeURLSelector(recorder: recorder, url: URL(string: "https://example.com/a.mov")!),
            downloader: FakeDownloader(recorder: recorder),
            brightnessStore: NoopBrightnessStore(),
            storeEditor: RepairingStoreEditor(recorder: recorder),
            reloader: FakeReloader(recorder: recorder),
            stateStore: state,
            now: { Date(timeIntervalSince1970: 1) }
        )

        _ = try await engine.next(
            settings: Settings(
                excludedCategoryIDs: [],
                excludedSubcategoryIDs: [],
                excludedAssetIDs: [],
                randomMode: false,
                downloadTimeout: 5,
                indexPlistURL: URL(fileURLWithPath: "/Users/test/Index.plist"),
                backupRetentionCount: 10,
                isLightSensitiveFilteringEnabled: false,
                allowedLightStartMinutes: 10 * 60,
                allowedLightEndMinutes: 18 * 60,
                lightSensitivity: 0.5
            )
        )

        let events = recorder.snapshot()
        #expect(events == ["pick", "url", "download", "apply", "repair", "apply", "reload"])
    }

    @Test func testNext_propagatesCatalogLoadFailure() async {
        let recorder = Recorder()
        let state = FakeEngineStateStore(lastAssetID: nil)

        let engine = AerialEngine(
            catalog: FailingCatalog(),
            picker: FakePicker(recorder: recorder),
            urlSelector: FakeURLSelector(recorder: recorder, url: URL(string: "https://example.com/a.mov")!),
            downloader: FakeDownloader(recorder: recorder),
            brightnessStore: NoopBrightnessStore(),
            storeEditor: FakeStoreEditor(recorder: recorder),
            reloader: FakeReloader(recorder: recorder),
            stateStore: state,
            now: { Date(timeIntervalSince1970: 1) }
        )

        do {
            _ = try await engine.next(
                settings: Settings(
                    excludedCategoryIDs: [],
                    excludedSubcategoryIDs: [],
                    excludedAssetIDs: [],
                    randomMode: false,
                    downloadTimeout: 5,
                    indexPlistURL: URL(fileURLWithPath: "/Users/test/Index.plist"),
                backupRetentionCount: 10,
                isLightSensitiveFilteringEnabled: false,
                allowedLightStartMinutes: 10 * 60,
                allowedLightEndMinutes: 18 * 60,
                lightSensitivity: 0.5
                )
            )
            #expect(Bool(false), "Expected catalog load failure to be thrown")
        } catch {
            // Expected: catalog failure propagates
            #expect(error is TestError)
        }

        // Verify no operations were attempted after catalog failure
        let events = recorder.snapshot()
        #expect(events.isEmpty)
    }

    @Test func testNext_neverPicksNonLandscapeMacAssets() async throws {
        let recorder = Recorder()
        // Current is the only landscape asset, so a naive picker would advance to the Mac asset.
        let state = FakeEngineStateStore(lastAssetID: "landscape")

        let assets = [
            AerialAsset(id: "landscape", categories: ["landscape-cat"], urlVariants: ["url-4K": URL(string: "https://example.com/landscape.mov")!]),
            AerialAsset(id: "mac", categories: ["mac-cat"], subcategories: ["mac-sub"], urlVariants: ["url-4K": URL(string: "https://example.com/mac.mov")!]),
        ]
        let categories = [
            AerialCategory(id: "landscape-cat", localizedNameKey: "AerialCategoryLandscapes"),
            AerialCategory(
                id: "mac-cat",
                localizedNameKey: "AerialCategoryMac",
                subcategories: [AerialCategory(id: "mac-sub", localizedNameKey: "AerialSubcategoryDescriptionMac")]
            ),
        ]
        let snapshot = AerialCatalog.Snapshot(
            assets: assets,
            categories: categories,
            fileURL: URL(fileURLWithPath: "/dev/null"),
            fileModificationDate: nil
        )

        let engine = AerialEngine(
            catalog: FakeCatalog(snapshot: snapshot),
            picker: AssetPicker(),
            urlSelector: FakeURLSelector(recorder: recorder, url: URL(string: "https://example.com/landscape.mov")!),
            downloader: FakeDownloader(recorder: recorder),
            brightnessStore: NoopBrightnessStore(),
            storeEditor: FakeStoreEditor(recorder: recorder),
            reloader: FakeReloader(recorder: recorder),
            stateStore: state,
            now: { Date(timeIntervalSince1970: 1) }
        )

        let report = try await engine.next(
            settings: Settings(
                excludedCategoryIDs: [],
                excludedSubcategoryIDs: [],
                excludedAssetIDs: [],
                randomMode: false,
                downloadTimeout: 5,
                indexPlistURL: URL(fileURLWithPath: "/Users/test/Index.plist"),
                backupRetentionCount: 10,
                isLightSensitiveFilteringEnabled: false,
                allowedLightStartMinutes: 10 * 60,
                allowedLightEndMinutes: 18 * 60,
                lightSensitivity: 0.5
            )
        )

        // Only the landscape asset is eligible; it wraps back to itself rather than picking "mac".
        #expect(report.chosenAssetID == "landscape")
    }

    @Test func testApply_appliesSpecificAsset_withoutPicking() async throws {
        let recorder = Recorder()
        let state = FakeEngineStateStore(lastAssetID: "a")

        let assets = [
            AerialAsset(id: "a", categories: [], urlVariants: ["url-4K": URL(string: "https://example.com/a.mov")!]),
            AerialAsset(id: "b", categories: [], urlVariants: ["url-4K": URL(string: "https://example.com/b.mov")!]),
        ]
        let catalogSnapshot = AerialCatalog.Snapshot(assets: assets, categories: [], fileURL: URL(fileURLWithPath: "/dev/null"), fileModificationDate: nil)

        let engine = AerialEngine(
            catalog: FakeCatalog(snapshot: catalogSnapshot),
            picker: FakePicker(recorder: recorder),
            urlSelector: FakeURLSelector(recorder: recorder, url: URL(string: "https://example.com/b.mov")!),
            downloader: FakeDownloader(recorder: recorder),
            brightnessStore: NoopBrightnessStore(),
            storeEditor: FakeStoreEditor(recorder: recorder),
            reloader: FakeReloader(recorder: recorder),
            stateStore: state,
            now: { Date(timeIntervalSince1970: 1) }
        )

        let report = try await engine.apply(
            assetID: "b",
            settings: Settings(
                excludedCategoryIDs: [],
                excludedSubcategoryIDs: [],
                excludedAssetIDs: [],
                randomMode: false,
                downloadTimeout: 5,
                indexPlistURL: URL(fileURLWithPath: "/Users/test/Index.plist"),
                backupRetentionCount: 10,
                isLightSensitiveFilteringEnabled: false,
                allowedLightStartMinutes: 10 * 60,
                allowedLightEndMinutes: 18 * 60,
                lightSensitivity: 0.5
            )
        )

        #expect(report.chosenAssetID == "b")
        // Never invokes the picker: applies the requested asset directly.
        let events = recorder.snapshot()
        #expect(events == ["url", "download", "apply", "reload"])

        let lastAsset = await state.getLastAssetID()
        #expect(lastAsset == "b")
    }

    @Test func testApply_throwsAssetNotFound_whenAssetMissing() async {
        let recorder = Recorder()
        let state = FakeEngineStateStore(lastAssetID: "a")

        let assets = [
            AerialAsset(id: "a", categories: [], urlVariants: ["url-4K": URL(string: "https://example.com/a.mov")!]),
        ]
        let catalogSnapshot = AerialCatalog.Snapshot(assets: assets, categories: [], fileURL: URL(fileURLWithPath: "/dev/null"), fileModificationDate: nil)

        let engine = AerialEngine(
            catalog: FakeCatalog(snapshot: catalogSnapshot),
            picker: FakePicker(recorder: recorder),
            urlSelector: FakeURLSelector(recorder: recorder, url: URL(string: "https://example.com/a.mov")!),
            downloader: FakeDownloader(recorder: recorder),
            brightnessStore: NoopBrightnessStore(),
            storeEditor: FakeStoreEditor(recorder: recorder),
            reloader: FakeReloader(recorder: recorder),
            stateStore: state,
            now: { Date(timeIntervalSince1970: 1) }
        )

        do {
            _ = try await engine.apply(
                assetID: "missing",
                settings: Settings(
                    excludedCategoryIDs: [],
                    excludedSubcategoryIDs: [],
                    excludedAssetIDs: [],
                    randomMode: false,
                    downloadTimeout: 5,
                    indexPlistURL: URL(fileURLWithPath: "/Users/test/Index.plist"),
                    backupRetentionCount: 10,
                    isLightSensitiveFilteringEnabled: false,
                    allowedLightStartMinutes: 10 * 60,
                    allowedLightEndMinutes: 18 * 60,
                    lightSensitivity: 0.5
                )
            )
            #expect(Bool(false), "Expected assetNotFound to be thrown")
        } catch let error as AerialEngine.EngineError {
            guard case .assetNotFound(let assetID) = error else {
                #expect(Bool(false), "Expected assetNotFound, got \(error)")
                return
            }
            #expect(assetID == "missing")
        } catch {
            #expect(Bool(false), "Expected AerialEngine.EngineError, got \(error)")
        }

        // No pipeline work performed when the asset is missing.
        let events = recorder.snapshot()
        #expect(events.isEmpty)
    }

    @Test func testNextInSubcategory_filtersAssetsAndForcesNonRandomPick() async throws {
        let recorder = Recorder()
        let state = FakeEngineStateStore(lastAssetID: "b")

        let assets = [
            AerialAsset(id: "a", categories: [], subcategories: ["sub1"], urlVariants: ["url-4K": URL(string: "https://example.com/a.mov")!]),
            AerialAsset(id: "b", categories: [], subcategories: ["sub1"], urlVariants: ["url-4K": URL(string: "https://example.com/b.mov")!]),
            AerialAsset(id: "c", categories: [], subcategories: ["sub1"], urlVariants: ["url-4K": URL(string: "https://example.com/c.mov")!]),
            AerialAsset(id: "z", categories: [], subcategories: ["sub2"], urlVariants: ["url-4K": URL(string: "https://example.com/z.mov")!]),
        ]
        let catalogSnapshot = AerialCatalog.Snapshot(assets: assets, categories: [], fileURL: URL(fileURLWithPath: "/dev/null"), fileModificationDate: nil)

        let engine = AerialEngine(
            catalog: FakeCatalog(snapshot: catalogSnapshot),
            picker: AssetPicker(),
            urlSelector: FakeURLSelector(recorder: recorder, url: URL(string: "https://example.com/c.mov")!),
            downloader: FakeDownloader(recorder: recorder),
            brightnessStore: NoopBrightnessStore(),
            storeEditor: FakeStoreEditor(recorder: recorder),
            reloader: FakeReloader(recorder: recorder),
            stateStore: state,
            now: { Date(timeIntervalSince1970: 1) }
        )

        let report = try await engine.nextInSubcategory(
            settings: Settings(
                excludedCategoryIDs: [],
                excludedSubcategoryIDs: [],
                excludedAssetIDs: [],
                randomMode: true,
                downloadTimeout: 5,
                indexPlistURL: URL(fileURLWithPath: "/Users/test/Index.plist"),
                backupRetentionCount: 10,
                isLightSensitiveFilteringEnabled: false,
                allowedLightStartMinutes: 10 * 60,
                allowedLightEndMinutes: 18 * 60,
                lightSensitivity: 0.5
            ),
            subcategoryID: "sub1"
        )

        #expect(report.chosenAssetID == "c")
        let lastAsset = await state.getLastAssetID()
        #expect(lastAsset == "c")
    }
}


