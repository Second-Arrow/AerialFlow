import Foundation

/// Root container for Apple's `entries.json`.
struct AerialEntries: Decodable, Sendable {
    let assets: [AerialAsset]
    let categories: [AerialCategory]

    private enum CodingKeys: String, CodingKey {
        case assets
        case categories
    }

    init(assets: [AerialAsset], categories: [AerialCategory]) {
        self.assets = assets
        self.categories = categories
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.assets = (try? c.decode([AerialAsset].self, forKey: .assets)) ?? []
        self.categories = (try? c.decode([AerialCategory].self, forKey: .categories)) ?? []
    }
}


