import Foundation

enum VideoQualityPreference: String, Codable, Sendable {
    case prefer240fps
    case prefer4k
    case prefer1080
}

/// Selects the best download URL from the variants in `entries.json`.
struct AssetURLSelector: Sendable {
    enum SelectorError: LocalizedError {
        case noURLVariants(assetID: String)

        var errorDescription: String? {
            switch self {
            case .noURLVariants(let assetID):
                return "No URL variants available for asset \(assetID)."
            }
        }
    }

    init() {}

    func pickURL(for asset: AerialAsset, preference: VideoQualityPreference) throws -> URL {
        guard !asset.urlVariants.isEmpty else {
            throw SelectorError.noURLVariants(assetID: asset.id)
        }

        // Known high-value keys; keep the rest as fallback.
        // Note: Keep this logic deterministic; if multiple fallbacks match, pick the first by key sort.
        let keys = Array(asset.urlVariants.keys)

        let priority: [String]
        switch preference {
        case .prefer240fps:
            priority = [
                "url-4K-SDR-240FPS",
                "url-4K-HDR-240FPS",
                "url-4K-SDR",
                "url-4K-HDR",
                "url-4K",
                "url-1080p",
                "url-1080p-HDR",
            ]
        case .prefer4k:
            priority = [
                "url-4K-SDR",
                "url-4K-HDR",
                "url-4K",
                "url-4K-SDR-240FPS",
                "url-4K-HDR-240FPS",
                "url-1080p",
                "url-1080p-HDR",
            ]
        case .prefer1080:
            priority = [
                "url-1080p",
                "url-1080p-HDR",
                "url-4K-SDR",
                "url-4K",
                "url-4K-HDR",
                "url-4K-SDR-240FPS",
                "url-4K-HDR-240FPS",
            ]
        }

        for key in priority {
            if let url = asset.urlVariants[key] { return url }
        }

        // Fallback: any url-* key, deterministically.
        // Guard at top ensures urlVariants is non-empty, so sorted()[0] is safe.
        let sortedKeys = keys.sorted()
        // The guard at top guarantees non-empty, but use safe subscript pattern.
        guard let fallbackKey = sortedKeys.first,
              let fallbackURL = asset.urlVariants[fallbackKey] else {
            // Unreachable due to guard at top, but satisfy compiler.
            throw SelectorError.noURLVariants(assetID: asset.id)
        }
        return fallbackURL
    }
}

// MARK: - Protocol Conformance

extension AssetURLSelector: AssetURLSelecting {}


