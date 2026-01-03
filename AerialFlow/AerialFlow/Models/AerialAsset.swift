import Foundation

/// A single Aerial video entry as described in Apple's `entries.json`.
///
/// Parsing is intentionally tolerant:
/// - Missing `categories` becomes `[]`
/// - Unknown `url-*` keys are preserved in `urlVariants`
struct AerialAsset: Decodable, Hashable, Sendable {
    let id: String
    let categories: [String]
    let subcategories: [String]
    let localizedNameKey: String?
    let shotID: String?
    let urlVariants: [String: URL]

    private enum KnownKeys: String, CodingKey {
        case id
        case categories
        case subcategories
        case localizedNameKey
        case shotID
    }

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(
        id: String,
        categories: [String],
        subcategories: [String] = [],
        localizedNameKey: String? = nil,
        shotID: String? = nil,
        urlVariants: [String: URL]
    ) {
        self.id = id
        self.categories = categories
        self.subcategories = subcategories
        self.localizedNameKey = localizedNameKey
        self.shotID = shotID
        self.urlVariants = urlVariants
    }

    init(from decoder: Decoder) throws {
        let known = try decoder.container(keyedBy: KnownKeys.self)
        let dynamic = try decoder.container(keyedBy: DynamicKey.self)

        self.id = (try? known.decode(String.self, forKey: .id)) ?? ""
        self.categories = (try? known.decode([String].self, forKey: .categories)) ?? []
        self.subcategories = (try? known.decode([String].self, forKey: .subcategories)) ?? []
        self.localizedNameKey = try? known.decode(String.self, forKey: .localizedNameKey)
        self.shotID = try? known.decode(String.self, forKey: .shotID)

        var variants: [String: URL] = [:]
        for key in dynamic.allKeys where key.stringValue.hasPrefix("url-") {
            // Some catalogs store urls as strings.
            if let urlString = try? dynamic.decode(String.self, forKey: key),
               let url = URL(string: urlString) {
                variants[key.stringValue] = url
            } else if let url = try? dynamic.decode(URL.self, forKey: key) {
                variants[key.stringValue] = url
            }
        }
        self.urlVariants = variants
    }
}

extension AerialAsset {
    /// All category IDs associated with the asset (top-level categories + subcategories).
    var allCategoryIDs: Set<String> {
        Set(categories).union(subcategories)
    }

    func isExcluded(
        excludedMainCategoryIDs: Set<String>,
        excludedSubcategoryIDs: Set<String>
    ) -> Bool {
        if !excludedMainCategoryIDs.isEmpty {
            let mainIDs = Set(categories)
            if !excludedMainCategoryIDs.isDisjoint(with: mainIDs) {
                return true
            }
        }

        if !excludedSubcategoryIDs.isEmpty {
            let subIDs = Set(subcategories)
            if !excludedSubcategoryIDs.isDisjoint(with: subIDs) {
                return true
            }
        }

        return false
    }
}


