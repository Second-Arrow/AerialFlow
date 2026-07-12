import Testing
import Foundation
@testable import AerialFlow

struct AerialAssetDecodingTests {
    @Test func testDecodesPreviewImageURL() throws {
        let json = """
        {
          "id": "asset-1",
          "categories": ["earth"],
          "subcategories": ["sub-1"],
          "previewImage": "https://example.com/preview.png",
          "url-4K": "https://example.com/video.mov"
        }
        """

        let data = try #require(json.data(using: .utf8))
        let asset = try JSONDecoder().decode(AerialAsset.self, from: data)

        #expect(asset.id == "asset-1")
        #expect(asset.previewImageURL == URL(string: "https://example.com/preview.png"))
    }

    @Test func testDecodesAccessibilityLabel() throws {
        let json = """
        {
          "id": "asset-1",
          "categories": ["earth"],
          "accessibilityLabel": "Tahoe Day",
          "url-4K": "https://example.com/video.mov"
        }
        """

        let data = try #require(json.data(using: .utf8))
        let asset = try JSONDecoder().decode(AerialAsset.self, from: data)

        #expect(asset.accessibilityLabel == "Tahoe Day")
    }

    @Test func testAccessibilityLabel_defaultsToNilWhenAbsent() throws {
        let json = """
        {
          "id": "asset-1",
          "categories": ["earth"]
        }
        """

        let data = try #require(json.data(using: .utf8))
        let asset = try JSONDecoder().decode(AerialAsset.self, from: data)

        #expect(asset.accessibilityLabel == nil)
    }
}


