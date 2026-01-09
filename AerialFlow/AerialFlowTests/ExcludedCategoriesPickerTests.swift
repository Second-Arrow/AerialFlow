import Foundation
import Testing
@testable import AerialFlow

struct ExcludedCategoriesPickerTests {
    @Test func testRows_sortsAssetsByLocalizedNameKeyWhenPresent_otherwiseByID() throws {
        let main = AerialCategory(id: "main", localizedNameKey: "Main", subcategories: [])

        func asset(id: String, localizedNameKey: String?) -> AerialAsset {
            AerialAsset(
                id: id,
                categories: ["main"],
                subcategories: [],
                localizedNameKey: localizedNameKey,
                urlVariants: ["url-4K": URL(string: "https://example.com/\(id).mov")!]
            )
        }

        // Derived sort keys:
        // - ZZZ (key AAA) => AAA
        // - BBB (key nil) => BBB
        // - AAC (key "")  => AAC
        // - AAA (key "AAA") => AAA (tie with ZZZ, then by id)
        let assets: [AerialAsset] = [
            asset(id: "BBB", localizedNameKey: nil),
            asset(id: "ZZZ", localizedNameKey: "AAA"),
            asset(id: "AAC", localizedNameKey: ""),
            asset(id: "AAA", localizedNameKey: "AAA"),
        ]

        let rows = ExclusionRow.rows(fromMainCategories: [main], assets: assets)
        let orderedAssetIDs = rows.compactMap(\.assetID)

        #expect(orderedAssetIDs == ["AAA", "ZZZ", "AAC", "BBB"])
    }

    @Test func testRows_handlesNilAndEmptyLocalizedNameKey_withoutCrashing() throws {
        let main = AerialCategory(id: "main", localizedNameKey: "Main", subcategories: [])

        let aNil = AerialAsset(
            id: "B",
            categories: ["main"],
            subcategories: [],
            localizedNameKey: nil,
            urlVariants: ["url-4K": URL(string: "https://example.com/B.mov")!]
        )
        let aEmpty = AerialAsset(
            id: "A",
            categories: ["main"],
            subcategories: [],
            localizedNameKey: "",
            urlVariants: ["url-4K": URL(string: "https://example.com/A.mov")!]
        )

        let rows = ExclusionRow.rows(fromMainCategories: [main], assets: [aNil, aEmpty])
        let orderedAssetIDs = rows.compactMap(\.assetID)

        // Both nil and empty fall back to id, so normal string ordering applies.
        #expect(orderedAssetIDs == ["A", "B"])
    }
}

