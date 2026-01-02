import Foundation

/// A single Aerial video entry as described in Apple's `entries.json`.
///
/// Parsing is intentionally tolerant:
/// - Missing `categories` becomes `[]`
/// - Unknown `url-*` keys are preserved in `urlVariants`
struct AerialAsset: Decodable, Hashable, Sendable {
    let id: String
    let categories: [String]
    let urlVariants: [String: URL]

    private enum KnownKeys: String, CodingKey {
        case id
        case categories
    }

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(id: String, categories: [String], urlVariants: [String: URL]) {
        self.id = id
        self.categories = categories
        self.urlVariants = urlVariants
    }

    init(from decoder: Decoder) throws {
        let known = try decoder.container(keyedBy: KnownKeys.self)
        let dynamic = try decoder.container(keyedBy: DynamicKey.self)

        self.id = (try? known.decode(String.self, forKey: .id)) ?? ""
        self.categories = (try? known.decode([String].self, forKey: .categories)) ?? []

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


