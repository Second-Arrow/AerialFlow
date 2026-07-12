import Foundation
import Testing

@testable import AerialFlow

struct NonLandscapeAerialFilterTests {
    private func asset(_ id: String, categories: [String] = [], subcategories: [String] = []) -> AerialAsset {
        AerialAsset(id: id, categories: categories, subcategories: subcategories, urlVariants: [:])
    }

    /// Mirrors the macOS 26 catalog shape: a landscape category and a "Mac" category.
    private func macAndLandscapeCategories() -> [AerialCategory] {
        [
            AerialCategory(
                id: "landscape-cat",
                localizedNameKey: "AerialCategoryLandscapes",
                subcategories: [AerialCategory(id: "tahoe-sub", localizedNameKey: "AerialSubcategoryTahoe")]
            ),
            AerialCategory(
                id: "mac-cat",
                localizedNameKey: "AerialCategoryMac",
                subcategories: [AerialCategory(id: "mac-sub", localizedNameKey: "AerialSubcategoryDescriptionMac")]
            ),
        ]
    }

    @Test func testFilter_removesAssetsInMacMainCategory() {
        let assets = [
            asset("landscape", categories: ["landscape-cat"], subcategories: ["tahoe-sub"]),
            asset("mac", categories: ["mac-cat"], subcategories: ["mac-sub"]),
        ]

        let result = NonLandscapeAerialFilter().filter(assets: assets, categories: macAndLandscapeCategories())

        #expect(result.map(\.id) == ["landscape"])
    }

    @Test func testFilter_removesAssetsReferencingOnlyMacSubcategory() {
        let assets = [
            asset("landscape", categories: ["landscape-cat"], subcategories: ["tahoe-sub"]),
            asset("mac-by-sub", categories: [], subcategories: ["mac-sub"]),
        ]

        let result = NonLandscapeAerialFilter().filter(assets: assets, categories: macAndLandscapeCategories())

        #expect(result.map(\.id) == ["landscape"])
    }

    @Test func testFilter_noMacCategory_isNoOp() {
        // Legacy catalog (macOS 15): no Mac category present.
        let categories = [
            AerialCategory(
                id: "landscape-cat",
                localizedNameKey: "AerialCategoryLandscapes",
                subcategories: [AerialCategory(id: "tahoe-sub", localizedNameKey: "AerialSubcategoryTahoe")]
            )
        ]
        let assets = [
            asset("a", categories: ["landscape-cat"], subcategories: ["tahoe-sub"]),
            asset("b", categories: ["landscape-cat"]),
        ]

        let result = NonLandscapeAerialFilter().filter(assets: assets, categories: categories)

        #expect(result.map(\.id) == ["a", "b"])
    }

    @Test func testFilter_emptyCategories_returnsAllAssets() {
        let assets = [asset("a"), asset("b")]

        let result = NonLandscapeAerialFilter().filter(assets: assets, categories: [])

        #expect(result.map(\.id) == ["a", "b"])
    }

    @Test func testFilterCategories_removesMacCategorySubtree() {
        let result = NonLandscapeAerialFilter().filter(categories: macAndLandscapeCategories())

        #expect(result.map(\.id) == ["landscape-cat"])
        #expect(result.first?.subcategories.map(\.id) == ["tahoe-sub"])
    }

    @Test func testFilterCategories_noMacCategory_isNoOp() {
        let categories = [
            AerialCategory(
                id: "landscape-cat",
                localizedNameKey: "AerialCategoryLandscapes",
                subcategories: [AerialCategory(id: "tahoe-sub", localizedNameKey: "AerialSubcategoryTahoe")]
            )
        ]

        let result = NonLandscapeAerialFilter().filter(categories: categories)

        #expect(result.map(\.id) == ["landscape-cat"])
        #expect(result.first?.subcategories.map(\.id) == ["tahoe-sub"])
    }
}
