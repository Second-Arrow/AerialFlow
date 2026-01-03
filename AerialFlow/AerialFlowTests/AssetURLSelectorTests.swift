import Foundation
import Testing

@testable import AerialFlow

struct AssetURLSelectorTests {
    @Test func testPickURL_returnsFirstAvailableURL() throws {
        let asset = AerialAsset(
            id: "ASSET",
            categories: [],
            urlVariants: [
                "url-4K-SDR-240FPS": URL(string: "https://example.com/sdr240.mov")!,
            ]
        )
        let selector = AssetURLSelector()
        let url = try selector.pickURL(for: asset)
        #expect(url.absoluteString == "https://example.com/sdr240.mov")
    }

    @Test func testPickURL_picksDeterministicFirstKey() throws {
        let asset = AerialAsset(
            id: "ASSET",
            categories: [],
            urlVariants: [
                "url-z": URL(string: "https://example.com/z.mov")!,
                "url-a": URL(string: "https://example.com/a.mov")!,
            ]
        )
        let selector = AssetURLSelector()
        let url = try selector.pickURL(for: asset)
        #expect(url.absoluteString == "https://example.com/a.mov")
    }

    @Test func testPickURL_throwsWhenNoVariants() throws {
        let asset = AerialAsset(
            id: "ASSET",
            categories: [],
            urlVariants: [:]
        )
        let selector = AssetURLSelector()
        #expect(throws: AssetURLSelector.SelectorError.noURLVariants(assetID: "ASSET")) {
            try selector.pickURL(for: asset)
        }
    }
}


