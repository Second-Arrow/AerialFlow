import Foundation

/// A category as described in Apple's `entries.json`.
struct AerialCategory: Decodable, Hashable, Sendable {
    let id: String
    let localizedNameKey: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case localizedNameKey
    }

    init(id: String, localizedNameKey: String?) {
        self.id = id
        self.localizedNameKey = localizedNameKey
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(String.self, forKey: .id)) ?? ""
        self.localizedNameKey = try? c.decode(String.self, forKey: .localizedNameKey)
    }
}


