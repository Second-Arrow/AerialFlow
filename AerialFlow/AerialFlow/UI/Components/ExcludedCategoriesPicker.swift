import SwiftUI
import AppKit

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
        let ak = a.localizedNameKey?.isEmpty == false ? a.localizedNameKey! : a.id
        let bk = b.localizedNameKey?.isEmpty == false ? b.localizedNameKey! : b.id
        if ak != bk { return ak < bk }
        return a.id < b.id
    }
}

struct ExcludedCategoriesPicker: View {
    let rows: [ExclusionRow]
    let categoryDisplayNameByID: [String: String]
    let assetDisplayNameByID: [String: String]
    @Binding var excludedCategoryIDs: Set<String>
    @Binding var excludedSubcategoryIDs: Set<String>
    @Binding var excludedAssetIDs: Set<String>
    @Binding var searchText: String
    let currentAssetID: String?

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 12) {
                SettingsRow("Search", labelWidth: 70) {
                    HStack(spacing: 10) {
                        TextField("Category, subcategory, or asset name", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)

                        Button("Current") {
                            guard let currentAssetID, !currentAssetID.isEmpty else { return }
                            withAnimation { searchText = "" }
                            DispatchQueue.main.async {
                                proxy.scrollTo("asset:\(currentAssetID)", anchor: .center)
                            }
                        }
                        .disabled(currentAssetID == nil || currentAssetID?.isEmpty == true)
                        .help("Scroll to the currently active Aerial.")
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)
                    }
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredRows, id: \.self) { row in
                            Toggle(isOn: bindingForRow(row)) {
                                HStack(spacing: 8) {
                                    Color.clear
                                        .frame(width: CGFloat(row.depth) * 14)
                                    Text(displayName(for: row))
                                        .strikethrough(isRowExcluded(row))
                                    Spacer()
                                    if let assetID = row.assetID, assetID == currentAssetID {
                                        Text("current")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color(nsColor: .quaternaryLabelColor).opacity(0.3))
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                }
                            }
                            .disabled(isRowDisabled(row))
                            .help("When enabled, this item will never be selected.")
                            .padding(.vertical, 6)
                            .id(scrollID(for: row))

                            Divider()
                        }
                    }
                    .padding(.horizontal, 10)
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var filteredRows: [ExclusionRow] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return rows
        }

        let lower = trimmed.lowercased()
        return rows
            .filter { row in
                let name = displayName(for: row).lowercased()
                if name.contains(lower) { return true }
                if let categoryID = row.categoryID, categoryID.lowercased().contains(lower) { return true }
                if let assetID = row.assetID, assetID.lowercased().contains(lower) { return true }
                return false
            }
    }

    private func displayName(for row: ExclusionRow) -> String {
        switch row {
        case .category(let category, _, _):
            return categoryDisplayNameByID[category.id] ?? category.id
        case .asset(let assetID, _, _, _):
            return assetDisplayNameByID[assetID] ?? assetID
        }
    }

    private func isRowExcluded(_ row: ExclusionRow) -> Bool {
        switch row {
        case .category(let category, let depth, let rootMainCategoryID):
            if depth == 0 {
                return excludedCategoryIDs.contains(category.id)
            }
            return excludedSubcategoryIDs.contains(category.id) || excludedCategoryIDs.contains(rootMainCategoryID)
        case .asset(let assetID, _, let rootMainCategoryID, let parentSubcategoryID):
            if excludedAssetIDs.contains(assetID) { return true }
            if excludedCategoryIDs.contains(rootMainCategoryID) { return true }
            if let parentSubcategoryID, excludedSubcategoryIDs.contains(parentSubcategoryID) { return true }
            return false
        }
    }

    private func bindingForRow(_ row: ExclusionRow) -> Binding<Bool> {
        switch row {
        case .category(let category, let depth, _):
            if depth == 0 {
                return Binding(
                    get: { excludedCategoryIDs.contains(category.id) },
                    set: { isExcluded in
                        if isExcluded {
                            excludedCategoryIDs.insert(category.id)
                        } else {
                            excludedCategoryIDs.remove(category.id)
                        }
                    }
                )
            }

            return Binding(
                get: { excludedSubcategoryIDs.contains(category.id) },
                set: { isExcluded in
                    if isExcluded {
                        excludedSubcategoryIDs.insert(category.id)
                    } else {
                        excludedSubcategoryIDs.remove(category.id)
                    }
                }
            )
        case .asset(let assetID, _, _, _):
            return Binding(
                get: { excludedAssetIDs.contains(assetID) },
                set: { isExcluded in
                    if isExcluded {
                        excludedAssetIDs.insert(assetID)
                    } else {
                        excludedAssetIDs.remove(assetID)
                    }
                }
            )
        }
    }

    private func isRowDisabled(_ row: ExclusionRow) -> Bool {
        switch row {
        case .category(_, let depth, let rootMainCategoryID):
            // Subcategories are disabled when their main category is excluded.
            return depth > 0 && excludedCategoryIDs.contains(rootMainCategoryID)
        case .asset(_, _, let rootMainCategoryID, let parentSubcategoryID):
            // Assets are disabled when their parent category/subcategory is excluded (redundant).
            if excludedCategoryIDs.contains(rootMainCategoryID) { return true }
            if let parentSubcategoryID, excludedSubcategoryIDs.contains(parentSubcategoryID) { return true }
            return false
        }
    }

    private func scrollID(for row: ExclusionRow) -> String {
        switch row {
        case .category(let category, _, _):
            return "category:\(category.id)"
        case .asset(let assetID, _, _, _):
            // Intentionally global so the “Current” button can scroll to the first occurrence.
            return "asset:\(assetID)"
        }
    }
}


