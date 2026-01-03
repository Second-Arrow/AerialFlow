import Foundation

/// Selects a download URL from the variants in `entries.json`.
///
/// Since all assets currently only have `url-4K-SDR-240FPS`, this simply returns the first available URL.
struct AssetURLSelector: Sendable {
    enum SelectorError: LocalizedError, Equatable {
        case noURLVariants(assetID: String)

        var errorDescription: String? {
            switch self {
            case .noURLVariants(let assetID):
                return "No URL variants available for asset \(assetID)."
            }
        }
    }

    init() {}

    func pickURL(for asset: AerialAsset) throws -> URL {
        guard !asset.urlVariants.isEmpty else {
            throw SelectorError.noURLVariants(assetID: asset.id)
        }

        // Return the first available URL deterministically (sorted by key).
        // In practice, all assets currently only have `url-4K-SDR-240FPS`.
        let sortedKeys = asset.urlVariants.keys.sorted()
        guard let firstKey = sortedKeys.first,
              let url = asset.urlVariants[firstKey] else {
            // Unreachable due to guard at top, but satisfy compiler.
            throw SelectorError.noURLVariants(assetID: asset.id)
        }
        return url
    }
}

// MARK: - Protocol Conformance

extension AssetURLSelector: AssetURLSelecting {}


