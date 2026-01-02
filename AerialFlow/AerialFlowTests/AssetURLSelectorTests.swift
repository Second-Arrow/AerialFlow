import Foundation
import Testing

@testable import AerialFlow

struct AssetURLSelectorTests {
    @Test func testPrefer240_picksSdr240First() throws {
        let asset = AerialAsset(
            id: "ASSET",
            categories: [],
            urlVariants: [
                "url-4K-HDR-240FPS": URL(string: "https://example.com/hdr240.mov")!,
                "url-4K-SDR-240FPS": URL(string: "https://example.com/sdr240.mov")!,
            ]
        )
        let selector = AssetURLSelector()
        let url = try selector.pickURL(for: asset, preference: .prefer240fps)
        #expect(url.absoluteString == "https://example.com/sdr240.mov")
    }

    @Test func testPrefer240_fallsBackToHdr240() throws {
        let asset = AerialAsset(
            id: "ASSET",
            categories: [],
            urlVariants: [
                "url-4K-HDR-240FPS": URL(string: "https://example.com/hdr240.mov")!
            ]
        )
        let selector = AssetURLSelector()
        let url = try selector.pickURL(for: asset, preference: .prefer240fps)
        #expect(url.absoluteString == "https://example.com/hdr240.mov")
    }

    @Test func testFallback_picksDeterministicFirstKey() throws {
        let asset = AerialAsset(
            id: "ASSET",
            categories: [],
            urlVariants: [
                "url-z": URL(string: "https://example.com/z.mov")!,
                "url-a": URL(string: "https://example.com/a.mov")!,
            ]
        )
        let selector = AssetURLSelector()
        let url = try selector.pickURL(for: asset, preference: .prefer240fps)
        #expect(url.absoluteString == "https://example.com/a.mov")
    }
}


