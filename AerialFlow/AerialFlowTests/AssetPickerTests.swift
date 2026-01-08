import Foundation
import Testing

@testable import AerialFlow

struct AssetPickerTests {
    @Test func testSequential_wrapAround() throws {
        let assets = [
            AerialAsset(id: "b", categories: [], urlVariants: [:]),
            AerialAsset(id: "a", categories: [], urlVariants: [:]),
            AerialAsset(id: "c", categories: [], urlVariants: [:]),
        ]
        var rng = SeededRNG(seed: 1)
        let picker = AssetPicker()

        let nextFromC = try picker.pickNext(
            assets: assets,
            excludedCategoryIDs: [],
            excludedSubcategoryIDs: [],
            excludedAssetIDs: [],
            currentAssetID: "c",
            randomMode: false,
            rng: &rng
        )
        #expect(nextFromC.id == "a") // sorted order: a,b,c -> wrap
    }

    @Test func testSequential_currentNotFound_picksFirst() throws {
        let assets = [
            AerialAsset(id: "b", categories: [], urlVariants: [:]),
            AerialAsset(id: "a", categories: [], urlVariants: [:]),
        ]
        var rng = SeededRNG(seed: 1)
        let picker = AssetPicker()

        let next = try picker.pickNext(
            assets: assets,
            excludedCategoryIDs: [],
            excludedSubcategoryIDs: [],
            excludedAssetIDs: [],
            currentAssetID: "zzz",
            randomMode: false,
            rng: &rng
        )
        #expect(next.id == "a")
    }

    @Test func testExclusion_removesCandidates() throws {
        let assets = [
            AerialAsset(id: "a", categories: ["earth"], subcategories: ["sub-1"], urlVariants: [:]),
            AerialAsset(id: "b", categories: ["city"], urlVariants: [:]),
        ]
        var rng = SeededRNG(seed: 1)
        let picker = AssetPicker()

        let next = try picker.pickNext(
            assets: assets,
            excludedCategoryIDs: ["earth"],
            excludedSubcategoryIDs: [],
            excludedAssetIDs: [],
            currentAssetID: nil,
            randomMode: false,
            rng: &rng
        )
        #expect(next.id == "b")
    }

    @Test func testSubcategoryExclusion_removesCandidates() throws {
        let assets = [
            AerialAsset(id: "a", categories: ["earth"], subcategories: ["sub-1"], urlVariants: [:]),
            AerialAsset(id: "b", categories: ["earth"], subcategories: ["sub-2"], urlVariants: [:]),
        ]
        var rng = SeededRNG(seed: 1)
        let picker = AssetPicker()

        let next = try picker.pickNext(
            assets: assets,
            excludedCategoryIDs: [],
            excludedSubcategoryIDs: ["sub-1"],
            excludedAssetIDs: [],
            currentAssetID: nil,
            randomMode: false,
            rng: &rng
        )
        #expect(next.id == "b")
    }

    @Test func testRandom_prefersNotEqualToCurrentWhenPossible() throws {
        let assets = [
            AerialAsset(id: "a", categories: [], urlVariants: [:]),
            AerialAsset(id: "b", categories: [], urlVariants: [:]),
            AerialAsset(id: "c", categories: [], urlVariants: [:]),
        ]
        var rng = SeededRNG(seed: 42)
        let picker = AssetPicker()

        let next = try picker.pickNext(
            assets: assets,
            excludedCategoryIDs: [],
            excludedSubcategoryIDs: [],
            excludedAssetIDs: [],
            currentAssetID: "b",
            randomMode: true,
            rng: &rng
        )
        #expect(next.id != "b")
    }

    @Test func testAssetIDExclusion_removesCandidates() throws {
        let assets = [
            AerialAsset(id: "a", categories: ["earth"], urlVariants: [:]),
            AerialAsset(id: "b", categories: ["earth"], urlVariants: [:]),
        ]
        var rng = SeededRNG(seed: 1)
        let picker = AssetPicker()

        let next = try picker.pickNext(
            assets: assets,
            excludedCategoryIDs: [],
            excludedSubcategoryIDs: [],
            excludedAssetIDs: ["a"],
            currentAssetID: nil,
            randomMode: false,
            rng: &rng
        )
        #expect(next.id == "b")
    }
}


