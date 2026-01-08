import Testing
import Foundation
@testable import AerialFlow

struct AerialBrightnessStoreTests {
    private enum TestError: Error {
        case couldNotCreateUserDefaultsSuite
    }

    @Test func testCachesBrightnessByAssetID() async throws {
        let suiteName = "AerialFlowTests.AerialBrightnessStoreCaches.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.couldNotCreateUserDefaultsSuite
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let fs = InMemoryFileSystem()
        let counter = Counter()
        let downloader = FakeImageDownloader(fileSystem: fs, callCounter: counter, imageData: try TestImageFactory.pngData(rgba: (255, 255, 255, 255)))

        let store = AerialBrightnessStore(userDefaults: defaults, fileSystem: fs, downloader: downloader)

        let asset = AerialAsset(
            id: "a",
            categories: [],
            previewImageURL: URL(string: "https://example.com/a.png"),
            urlVariants: [:]
        )

        let first = try await store.brightness(for: asset, timeout: 1)
        let second = try await store.brightness(for: asset, timeout: 1)

        #expect(first > 0.95)
        #expect(second > 0.95)
        #expect(await counter.value == 1)
    }

    @Test func testPrecomputeSkipsAssetsWithoutPreviewImageURL() async throws {
        let suiteName = "AerialFlowTests.AerialBrightnessStoreSkips.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.couldNotCreateUserDefaultsSuite
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let fs = InMemoryFileSystem()
        let counter = Counter()
        let downloader = FakeImageDownloader(fileSystem: fs, callCounter: counter, imageData: try TestImageFactory.pngData(rgba: (255, 255, 255, 255)))

        let store = AerialBrightnessStore(userDefaults: defaults, fileSystem: fs, downloader: downloader)

        let assets = [
            AerialAsset(id: "no-preview", categories: [], previewImageURL: nil, urlVariants: [:]),
        ]

        await store.precompute(assets: assets, timeout: 1, maxConcurrency: 2)

        #expect(await counter.value == 0)
        #expect(await store.isDark(assetID: "no-preview", threshold: 0.5) == nil)
    }

    private struct FakeImageDownloader: Downloading {
        let fileSystem: InMemoryFileSystem
        let callCounter: Counter
        let imageData: Data

        func download(from url: URL, timeout: TimeInterval) async throws -> URL {
            _ = url
            _ = timeout
            await callCounter.increment()
            let tempURL = URL(fileURLWithPath: "/tmp/test-preview-\(UUID().uuidString).png")
            try fileSystem.writeData(imageData, to: tempURL, options: [])
            return tempURL
        }
    }
}


