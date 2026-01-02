import Foundation

/// Picks the next eligible Aerial asset given exclusions and current selection.
struct AssetPicker: Sendable {
    enum PickerError: LocalizedError {
        case noEligibleAssets

        var errorDescription: String? {
            switch self {
            case .noEligibleAssets:
                return "No eligible Aerial assets available after applying category exclusions."
            }
        }
    }

    init() {}

    func pickNext(
        assets: [AerialAsset],
        excludedCategoryIDs: Set<String>,
        currentAssetID: String?,
        randomMode: Bool,
        rng: inout some RandomNumberGenerator
    ) throws -> AerialAsset {
        let eligible = assets
            .filter { asset in
                guard !asset.id.isEmpty else { return false }
                if excludedCategoryIDs.isEmpty { return true }
                return excludedCategoryIDs.isDisjoint(with: Set(asset.categories))
            }
            .sorted { $0.id < $1.id } // stable, deterministic ordering

        guard !eligible.isEmpty else { throw PickerError.noEligibleAssets }

        if randomMode {
            if eligible.count == 1 { return eligible[0] }
            if let currentAssetID, eligible.contains(where: { $0.id == currentAssetID }) {
                // Prefer a random pick != current when possible.
                // Bound iterations to avoid infinite loop if RNG is pathological.
                var picked: AerialAsset
                var iterations = 0
                let maxIterations = eligible.count * 2
                repeat {
                    picked = eligible.randomElement(using: &rng) ?? eligible[0]
                    iterations += 1
                } while picked.id == currentAssetID && iterations < maxIterations
                return picked
            } else {
                return eligible.randomElement(using: &rng) ?? eligible[0]
            }
        }

        if let currentAssetID,
           let idx = eligible.firstIndex(where: { $0.id == currentAssetID }) {
            return eligible[(idx + 1) % eligible.count]
        }

        return eligible[0]
    }
}

// MARK: - Protocol Conformance

extension AssetPicker: AssetPicking {}


