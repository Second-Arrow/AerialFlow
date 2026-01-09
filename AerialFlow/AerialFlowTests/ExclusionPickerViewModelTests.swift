import Foundation
import SwiftUI
import Testing
@testable import AerialFlow

struct ExclusionPickerViewModelTests {
    @Test @MainActor func testFiltering_matchesOnDisplayNameOrIDs() {
        let main = AerialCategory(id: "main", localizedNameKey: "Main", subcategories: [])
        let rows: [ExclusionRow] = [
            .category(category: main, depth: 0, rootMainCategoryID: "main"),
            .asset(assetID: "asset1", depth: 1, rootMainCategoryID: "main", parentSubcategoryID: nil),
        ]

        var excludedCategoryIDs: Set<String> = []
        var excludedSubcategoryIDs: Set<String> = []
        var excludedAssetIDs: Set<String> = []
        var searchText: String = ""

        let model = ExclusionPickerViewModel(
            rows: rows,
            categoryDisplayNameByID: ["main": "BeautifulMain"],
            assetDisplayNameByID: ["asset1": "Golden Gate"],
            excludedCategoryIDs: Binding(get: { excludedCategoryIDs }, set: { excludedCategoryIDs = $0 }),
            excludedSubcategoryIDs: Binding(get: { excludedSubcategoryIDs }, set: { excludedSubcategoryIDs = $0 }),
            excludedAssetIDs: Binding(get: { excludedAssetIDs }, set: { excludedAssetIDs = $0 }),
            searchText: Binding(get: { searchText }, set: { searchText = $0 }),
            currentAssetID: nil
        )

        searchText = "gold"
        #expect(model.filteredRows == [rows[1]])

        searchText = "main"
        #expect(model.filteredRows == [rows[0]])

        searchText = "asset1"
        #expect(model.filteredRows == [rows[1]])
    }

    @Test @MainActor func testIsRowExcluded_respectsMainCategorySubcategoryAssetRules() {
        let main = AerialCategory(id: "main", localizedNameKey: "Main", subcategories: [])
        let sub = AerialCategory(id: "sub", localizedNameKey: "Sub", subcategories: [])

        let mainRow: ExclusionRow = .category(category: main, depth: 0, rootMainCategoryID: "main")
        let subRow: ExclusionRow = .category(category: sub, depth: 1, rootMainCategoryID: "main")
        let assetRow: ExclusionRow = .asset(assetID: "asset1", depth: 2, rootMainCategoryID: "main", parentSubcategoryID: "sub")

        var excludedCategoryIDs: Set<String> = []
        var excludedSubcategoryIDs: Set<String> = []
        var excludedAssetIDs: Set<String> = []
        var searchText: String = ""

        let model = ExclusionPickerViewModel(
            rows: [mainRow, subRow, assetRow],
            categoryDisplayNameByID: [:],
            assetDisplayNameByID: [:],
            excludedCategoryIDs: Binding(get: { excludedCategoryIDs }, set: { excludedCategoryIDs = $0 }),
            excludedSubcategoryIDs: Binding(get: { excludedSubcategoryIDs }, set: { excludedSubcategoryIDs = $0 }),
            excludedAssetIDs: Binding(get: { excludedAssetIDs }, set: { excludedAssetIDs = $0 }),
            searchText: Binding(get: { searchText }, set: { searchText = $0 }),
            currentAssetID: nil
        )

        // Main category exclusion excludes itself…
        excludedCategoryIDs = ["main"]
        #expect(model.isRowExcluded(mainRow) == true)

        // …and implies subcategory exclusion…
        #expect(model.isRowExcluded(subRow) == true)

        // …and implies asset exclusion.
        #expect(model.isRowExcluded(assetRow) == true)

        // Subcategory exclusion excludes the subcategory and its assets (but not the main category).
        excludedCategoryIDs = []
        excludedSubcategoryIDs = ["sub"]
        #expect(model.isRowExcluded(mainRow) == false)
        #expect(model.isRowExcluded(subRow) == true)
        #expect(model.isRowExcluded(assetRow) == true)

        // Asset exclusion excludes only that asset.
        excludedSubcategoryIDs = []
        excludedAssetIDs = ["asset1"]
        #expect(model.isRowExcluded(mainRow) == false)
        #expect(model.isRowExcluded(subRow) == false)
        #expect(model.isRowExcluded(assetRow) == true)
    }

    @Test @MainActor func testIsRowDisabled_disablesWhenParentExcluded() {
        let main = AerialCategory(id: "main", localizedNameKey: "Main", subcategories: [])
        let sub = AerialCategory(id: "sub", localizedNameKey: "Sub", subcategories: [])

        let mainRow: ExclusionRow = .category(category: main, depth: 0, rootMainCategoryID: "main")
        let subRow: ExclusionRow = .category(category: sub, depth: 1, rootMainCategoryID: "main")
        let assetUnderMain: ExclusionRow = .asset(assetID: "a", depth: 1, rootMainCategoryID: "main", parentSubcategoryID: nil)
        let assetUnderSub: ExclusionRow = .asset(assetID: "b", depth: 2, rootMainCategoryID: "main", parentSubcategoryID: "sub")

        var excludedCategoryIDs: Set<String> = []
        var excludedSubcategoryIDs: Set<String> = []
        var excludedAssetIDs: Set<String> = []
        var searchText: String = ""

        let model = ExclusionPickerViewModel(
            rows: [mainRow, subRow, assetUnderMain, assetUnderSub],
            categoryDisplayNameByID: [:],
            assetDisplayNameByID: [:],
            excludedCategoryIDs: Binding(get: { excludedCategoryIDs }, set: { excludedCategoryIDs = $0 }),
            excludedSubcategoryIDs: Binding(get: { excludedSubcategoryIDs }, set: { excludedSubcategoryIDs = $0 }),
            excludedAssetIDs: Binding(get: { excludedAssetIDs }, set: { excludedAssetIDs = $0 }),
            searchText: Binding(get: { searchText }, set: { searchText = $0 }),
            currentAssetID: nil
        )

        // Excluding the main category disables subcategories + all assets under it.
        excludedCategoryIDs = ["main"]
        #expect(model.isRowDisabled(mainRow) == false)
        #expect(model.isRowDisabled(subRow) == true)
        #expect(model.isRowDisabled(assetUnderMain) == true)
        #expect(model.isRowDisabled(assetUnderSub) == true)

        // Excluding the subcategory disables assets in that subcategory only.
        excludedCategoryIDs = []
        excludedSubcategoryIDs = ["sub"]
        #expect(model.isRowDisabled(subRow) == false)
        #expect(model.isRowDisabled(assetUnderMain) == false)
        #expect(model.isRowDisabled(assetUnderSub) == true)
    }
}

