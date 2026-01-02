import Foundation
import Testing

@testable import AerialFlow

struct AssetPickerTests {
    private struct SeededRNG: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { self.state = seed }
        mutating func next() -> UInt64 {
            // SplitMix64
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

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
            currentAssetID: "zzz",
            randomMode: false,
            rng: &rng
        )
        #expect(next.id == "a")
    }

    @Test func testExclusion_removesCandidates() throws {
        let assets = [
            AerialAsset(id: "a", categories: ["earth"], urlVariants: [:]),
            AerialAsset(id: "b", categories: ["city"], urlVariants: [:]),
        ]
        var rng = SeededRNG(seed: 1)
        let picker = AssetPicker()

        let next = try picker.pickNext(
            assets: assets,
            excludedCategoryIDs: ["earth"],
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
            currentAssetID: "b",
            randomMode: true,
            rng: &rng
        )
        #expect(next.id != "b")
    }
}


