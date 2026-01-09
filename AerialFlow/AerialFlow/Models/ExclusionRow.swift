import Foundation

enum ExclusionRow: Hashable, Sendable {
    case category(category: AerialCategory, depth: Int, rootMainCategoryID: String)
    case asset(assetID: String, depth: Int, rootMainCategoryID: String, parentSubcategoryID: String?)

    var depth: Int {
        switch self {
        case .category(_, let depth, _):
            return depth
        case .asset(_, let depth, _, _):
            return depth
        }
    }

    var rootMainCategoryID: String {
        switch self {
        case .category(_, _, let rootMainCategoryID):
            return rootMainCategoryID
        case .asset(_, _, let rootMainCategoryID, _):
            return rootMainCategoryID
        }
    }

    var categoryID: String? {
        switch self {
        case .category(let category, _, _):
            return category.id
        case .asset:
            return nil
        }
    }

    var assetID: String? {
        switch self {
        case .category:
            return nil
        case .asset(let assetID, _, _, _):
            return assetID
        }
    }

    var parentSubcategoryID: String? {
        switch self {
        case .category:
            return nil
        case .asset(_, _, _, let parentSubcategoryID):
            return parentSubcategoryID
        }
    }

    var isMainCategory: Bool {
        switch self {
        case .category(_, let depth, _):
            return depth == 0
        case .asset:
            return false
        }
    }

    var isSubcategory: Bool {
        switch self {
        case .category(_, let depth, _):
            return depth > 0
        case .asset:
            return false
        }
    }

    static func rows(
        fromMainCategories categories: [AerialCategory],
        assets: [AerialAsset]
    ) -> [ExclusionRow] {
        var out: [ExclusionRow] = []
        out.reserveCapacity(categories.count)

        for main in categories {
            guard !main.id.isEmpty else { continue }
            out.append(.category(category: main, depth: 0, rootMainCategoryID: main.id))

            // Subcategories (and deeper) first…
            appendSubcategoriesAndAssets(of: main, depth: 1, rootMainCategoryID: main.id, assets: assets, into: &out)

            // …then assets that have no subcategory (still belong to the main category).
            let directAssets = assets
                .filter { asset in
                    guard !asset.id.isEmpty else { return false }
                    guard asset.categories.contains(main.id) else { return false }
                    return asset.subcategories.isEmpty
                }
                .sorted(by: sortAssetsByPreferredDisplayKeyThenID)

            for asset in directAssets {
                out.append(.asset(assetID: asset.id, depth: 1, rootMainCategoryID: main.id, parentSubcategoryID: nil))
            }
        }

        return out
    }

    private static func appendSubcategoriesAndAssets(
        of category: AerialCategory,
        depth: Int,
        rootMainCategoryID: String,
        assets: [AerialAsset],
        into out: inout [ExclusionRow]
    ) {
        for sub in category.subcategories.sorted(by: AerialCategory.sortByPreferredOrderThenID) {
            guard !sub.id.isEmpty else { continue }

            out.append(.category(category: sub, depth: depth, rootMainCategoryID: rootMainCategoryID))

            let assetsForSub = assets
                .filter { asset in
                    guard !asset.id.isEmpty else { return false }
                    guard asset.categories.contains(rootMainCategoryID) else { return false }
                    return asset.subcategories.contains(sub.id)
                }
                .sorted(by: sortAssetsByPreferredDisplayKeyThenID)

            for asset in assetsForSub {
                out.append(.asset(assetID: asset.id, depth: depth + 1, rootMainCategoryID: rootMainCategoryID, parentSubcategoryID: sub.id))
            }

            appendSubcategoriesAndAssets(of: sub, depth: depth + 1, rootMainCategoryID: rootMainCategoryID, assets: assets, into: &out)
        }
    }

    /// Stable ordering for assets within a category/subcategory.
    /// We prefer `localizedNameKey` (so ordering roughly matches UI labels) but fall back to `id`.
    private static func sortAssetsByPreferredDisplayKeyThenID(_ a: AerialAsset, _ b: AerialAsset) -> Bool {
        let ak = a.localizedNameKey.flatMap { $0.isEmpty ? nil : $0 } ?? a.id
        let bk = b.localizedNameKey.flatMap { $0.isEmpty ? nil : $0 } ?? b.id
        if ak != bk { return ak < bk }
        return a.id < b.id
    }
}

