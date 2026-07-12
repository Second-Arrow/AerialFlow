import Foundation

/// Removes non-landscape Aerials (e.g. the portrait "Mac" wallpapers introduced on macOS 26)
/// from a set of candidate assets before selection.
///
/// Identification is catalog-driven and version-proof: it matches categories by their stable
/// `localizedNameKey` (default `AerialCategoryMac`) rather than by GUID, then excludes any asset
/// referencing those categories or their subcategories.
///
/// Backward compatible: legacy catalogs (macOS 15 and earlier) contain no such category, so this
/// filter is a no-op there.
struct NonLandscapeAerialFilter: Sendable {
    /// Stable category `localizedNameKey`s to treat as non-landscape.
    static let defaultExcludedCategoryNameKeys: Set<String> = ["AerialCategoryMac"]

    private let excludedCategoryNameKeys: Set<String>

    init(excludedCategoryNameKeys: Set<String> = NonLandscapeAerialFilter.defaultExcludedCategoryNameKeys) {
        self.excludedCategoryNameKeys = excludedCategoryNameKeys
    }

    /// Returns `assets` with all non-landscape assets removed.
    func filter(assets: [AerialAsset], categories: [AerialCategory]) -> [AerialAsset] {
        let excludedIDs = excludedCategoryIDs(in: categories)
        guard !excludedIDs.isEmpty else { return assets }

        return assets.filter { $0.allCategoryIDs.isDisjoint(with: excludedIDs) }
    }

    /// Returns `categories` with any non-landscape category subtrees removed.
    ///
    /// Used to hide non-landscape categories (e.g. "Mac") from user-facing lists such as the
    /// Exclusions screen. No-op when no matching category is present.
    func filter(categories: [AerialCategory]) -> [AerialCategory] {
        guard !excludedCategoryNameKeys.isEmpty else { return categories }

        return categories.compactMap { prune($0) }
    }

    private func prune(_ category: AerialCategory) -> AerialCategory? {
        if let key = category.localizedNameKey, excludedCategoryNameKeys.contains(key) {
            return nil
        }
        let prunedSubcategories = category.subcategories.compactMap { prune($0) }
        return AerialCategory(
            id: category.id,
            localizedNameKey: category.localizedNameKey,
            localizedDescriptionKey: category.localizedDescriptionKey,
            preferredOrder: category.preferredOrder,
            previewImage: category.previewImage,
            representativeAssetID: category.representativeAssetID,
            subcategories: prunedSubcategories
        )
    }

    /// Collects the IDs of every matching category node plus all of its descendant categories.
    private func excludedCategoryIDs(in categories: [AerialCategory]) -> Set<String> {
        guard !excludedCategoryNameKeys.isEmpty else { return [] }

        var result: Set<String> = []
        for category in categories {
            collect(category, into: &result)
        }
        return result
    }

    private func collect(_ category: AerialCategory, into result: inout Set<String>) {
        if let key = category.localizedNameKey, excludedCategoryNameKeys.contains(key) {
            insertSubtreeIDs(category, into: &result)
            return
        }
        for sub in category.subcategories {
            collect(sub, into: &result)
        }
    }

    private func insertSubtreeIDs(_ category: AerialCategory, into result: inout Set<String>) {
        if !category.id.isEmpty { result.insert(category.id) }
        for sub in category.subcategories {
            insertSubtreeIDs(sub, into: &result)
        }
    }
}
