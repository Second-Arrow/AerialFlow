import Foundation

/// A category as described in Apple's `entries.json`.
struct AerialCategory: Decodable, Hashable, Sendable {
    let id: String
    let localizedNameKey: String?
    let localizedDescriptionKey: String?
    let preferredOrder: Int?
    let previewImage: String?
    let representativeAssetID: String?
    let subcategories: [AerialCategory]

    private enum CodingKeys: String, CodingKey {
        case id
        case localizedNameKey
        case localizedDescriptionKey
        case preferredOrder
        case previewImage
        case representativeAssetID
        case subcategories
    }

    init(
        id: String,
        localizedNameKey: String?,
        localizedDescriptionKey: String? = nil,
        preferredOrder: Int? = nil,
        previewImage: String? = nil,
        representativeAssetID: String? = nil,
        subcategories: [AerialCategory] = []
    ) {
        self.id = id
        self.localizedNameKey = localizedNameKey
        self.localizedDescriptionKey = localizedDescriptionKey
        self.preferredOrder = preferredOrder
        self.previewImage = previewImage
        self.representativeAssetID = representativeAssetID
        self.subcategories = subcategories
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(String.self, forKey: .id)) ?? ""
        self.localizedNameKey = try? c.decode(String.self, forKey: .localizedNameKey)
        self.localizedDescriptionKey = try? c.decode(String.self, forKey: .localizedDescriptionKey)
        self.preferredOrder = try? c.decode(Int.self, forKey: .preferredOrder)
        self.previewImage = try? c.decode(String.self, forKey: .previewImage)
        self.representativeAssetID = try? c.decode(String.self, forKey: .representativeAssetID)
        self.subcategories = (try? c.decode([AerialCategory].self, forKey: .subcategories)) ?? []
    }
}

extension AerialCategory {
    /// Depth-first pre-order traversal (parent before children), retaining indentation depth.
    static func flattenWithDepth(_ categories: [AerialCategory]) -> [(category: AerialCategory, depth: Int)] {
        var out: [(category: AerialCategory, depth: Int)] = []
        out.reserveCapacity(categories.count)
        for category in categories.sorted(by: sortByPreferredOrderThenID) {
            appendFlattened(category, depth: 0, into: &out)
        }
        return out
    }

    static func flatten(_ categories: [AerialCategory]) -> [AerialCategory] {
        flattenWithDepth(categories).map(\.category)
    }

    private static func appendFlattened(
        _ category: AerialCategory,
        depth: Int,
        into out: inout [(category: AerialCategory, depth: Int)]
    ) {
        out.append((category, depth))
        for sub in category.subcategories.sorted(by: sortByPreferredOrderThenID) {
            appendFlattened(sub, depth: depth + 1, into: &out)
        }
    }

    static func sortByPreferredOrderThenID(_ a: AerialCategory, _ b: AerialCategory) -> Bool {
        let ao = a.preferredOrder ?? Int.max
        let bo = b.preferredOrder ?? Int.max
        if ao != bo { return ao < bo }
        return a.id < b.id
    }

    /// Deduplicates top-level categories by `localizedNameKey` (fallback: `id`),
    /// keeping the earliest by `preferredOrder`, then `id`.
    static func uniqueMainCategories(_ categories: [AerialCategory]) -> [AerialCategory] {
        var bestByKey: [String: AerialCategory] = [:]
        bestByKey.reserveCapacity(categories.count)

        func key(for category: AerialCategory) -> String {
            if let k = category.localizedNameKey, !k.isEmpty { return k }
            return category.id
        }

        for category in categories {
            let k = key(for: category)
            if let existing = bestByKey[k] {
                if sortByPreferredOrderThenID(category, existing) {
                    bestByKey[k] = category
                }
            } else {
                bestByKey[k] = category
            }
        }

        return bestByKey.values.sorted(by: sortByPreferredOrderThenID)
    }
}


