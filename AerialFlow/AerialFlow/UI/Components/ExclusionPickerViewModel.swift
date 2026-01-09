import Combine
import SwiftUI

@MainActor
final class ExclusionPickerViewModel: ObservableObject {
    let rows: [ExclusionRow]
    let categoryDisplayNameByID: [String: String]
    let assetDisplayNameByID: [String: String]
    let excludedCategoryIDs: Binding<Set<String>>
    let excludedSubcategoryIDs: Binding<Set<String>>
    let excludedAssetIDs: Binding<Set<String>>
    let searchText: Binding<String>
    let currentAssetID: String?

    init(
        rows: [ExclusionRow],
        categoryDisplayNameByID: [String: String],
        assetDisplayNameByID: [String: String],
        excludedCategoryIDs: Binding<Set<String>>,
        excludedSubcategoryIDs: Binding<Set<String>>,
        excludedAssetIDs: Binding<Set<String>>,
        searchText: Binding<String>,
        currentAssetID: String?
    ) {
        self.rows = rows
        self.categoryDisplayNameByID = categoryDisplayNameByID
        self.assetDisplayNameByID = assetDisplayNameByID
        self.excludedCategoryIDs = excludedCategoryIDs
        self.excludedSubcategoryIDs = excludedSubcategoryIDs
        self.excludedAssetIDs = excludedAssetIDs
        self.searchText = searchText
        self.currentAssetID = currentAssetID
    }

    var filteredRows: [ExclusionRow] {
        let trimmed = searchText.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
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

    func displayName(for row: ExclusionRow) -> String {
        switch row {
        case .category(let category, _, _):
            return categoryDisplayNameByID[category.id] ?? category.id
        case .asset(let assetID, _, _, _):
            return assetDisplayNameByID[assetID] ?? assetID
        }
    }

    func isRowExcluded(_ row: ExclusionRow) -> Bool {
        switch row {
        case .category(let category, let depth, let rootMainCategoryID):
            if depth == 0 {
                return excludedCategoryIDs.wrappedValue.contains(category.id)
            }
            return excludedSubcategoryIDs.wrappedValue.contains(category.id) || excludedCategoryIDs.wrappedValue.contains(rootMainCategoryID)
        case .asset(let assetID, _, let rootMainCategoryID, let parentSubcategoryID):
            if excludedAssetIDs.wrappedValue.contains(assetID) { return true }
            if excludedCategoryIDs.wrappedValue.contains(rootMainCategoryID) { return true }
            if let parentSubcategoryID, excludedSubcategoryIDs.wrappedValue.contains(parentSubcategoryID) { return true }
            return false
        }
    }

    func bindingForRow(_ row: ExclusionRow) -> Binding<Bool> {
        switch row {
        case .category(let category, let depth, _):
            if depth == 0 {
                return Binding(
                    get: { self.excludedCategoryIDs.wrappedValue.contains(category.id) },
                    set: { isExcluded in
                        if isExcluded {
                            self.excludedCategoryIDs.wrappedValue.insert(category.id)
                        } else {
                            self.excludedCategoryIDs.wrappedValue.remove(category.id)
                        }
                    }
                )
            }

            return Binding(
                get: { self.excludedSubcategoryIDs.wrappedValue.contains(category.id) },
                set: { isExcluded in
                    if isExcluded {
                        self.excludedSubcategoryIDs.wrappedValue.insert(category.id)
                    } else {
                        self.excludedSubcategoryIDs.wrappedValue.remove(category.id)
                    }
                }
            )
        case .asset(let assetID, _, _, _):
            return Binding(
                get: { self.excludedAssetIDs.wrappedValue.contains(assetID) },
                set: { isExcluded in
                    if isExcluded {
                        self.excludedAssetIDs.wrappedValue.insert(assetID)
                    } else {
                        self.excludedAssetIDs.wrappedValue.remove(assetID)
                    }
                }
            )
        }
    }

    func isRowDisabled(_ row: ExclusionRow) -> Bool {
        switch row {
        case .category(_, let depth, let rootMainCategoryID):
            // Subcategories are disabled when their main category is excluded.
            return depth > 0 && excludedCategoryIDs.wrappedValue.contains(rootMainCategoryID)
        case .asset(_, _, let rootMainCategoryID, let parentSubcategoryID):
            // Assets are disabled when their parent category/subcategory is excluded (redundant).
            if excludedCategoryIDs.wrappedValue.contains(rootMainCategoryID) { return true }
            if let parentSubcategoryID, excludedSubcategoryIDs.wrappedValue.contains(parentSubcategoryID) { return true }
            return false
        }
    }

    func scrollID(for row: ExclusionRow) -> String {
        switch row {
        case .category(let category, _, _):
            return "category:\(category.id)"
        case .asset(let assetID, _, _, _):
            // Intentionally global so the “Current” button can scroll to the first occurrence.
            return "asset:\(assetID)"
        }
    }
}

