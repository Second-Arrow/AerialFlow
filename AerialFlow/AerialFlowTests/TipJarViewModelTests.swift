import XCTest
@testable import AerialFlow

@MainActor
final class TipJarViewModelTests: XCTestCase {
    func test_loadProducts_sortsAndExposesTiers() async {
        let purchaser = FakeTipJarPurchaser(
            products: [
                TipJarProduct(id: "b", displayName: "B", displayPrice: "$2", sortKey: 2),
                TipJarProduct(id: "a", displayName: "A", displayPrice: "$1", sortKey: 1)
            ],
            purchaseOutcomeByProductID: [:]
        )

        let model = TipJarViewModel(purchaser: purchaser, productIDs: ["a", "b"])
        await model.loadProducts()

        XCTAssertEqual(model.products.map(\.id), ["a", "b"])
        XCTAssertNil(model.errorMessage)
    }

    func test_purchase_success_setsThankYouState() async {
        let purchaser = FakeTipJarPurchaser(
            products: [],
            purchaseOutcomeByProductID: ["tip": .success]
        )
        let model = TipJarViewModel(purchaser: purchaser, productIDs: [])

        await model.purchase(productID: "tip")
        XCTAssertEqual(model.infoMessage, "Thank you for supporting AerialFlow.")
        XCTAssertNil(model.errorMessage)
    }

    func test_purchase_userCancelled_setsNonErrorMessage() async {
        let purchaser = FakeTipJarPurchaser(
            products: [],
            purchaseOutcomeByProductID: ["tip": .userCancelled]
        )
        let model = TipJarViewModel(purchaser: purchaser, productIDs: [])

        await model.purchase(productID: "tip")
        XCTAssertEqual(model.infoMessage, "Purchase cancelled.")
        XCTAssertNil(model.errorMessage)
    }

    func test_purchase_failure_setsErrorMessage() async {
        let purchaser = FakeTipJarPurchaser(
            products: [],
            purchaseOutcomeByProductID: ["tip": .failed(message: "Nope")]
        )
        let model = TipJarViewModel(purchaser: purchaser, productIDs: [])

        await model.purchase(productID: "tip")
        XCTAssertEqual(model.errorMessage, "Nope")
    }
}

private struct FakeTipJarPurchaser: TipJarPurchasing {
    let products: [TipJarProduct]
    let purchaseOutcomeByProductID: [String: TipJarPurchaseOutcome]

    func fetchProducts(productIDs: [String]) async throws -> [TipJarProduct] {
        products
    }

    func purchase(productID: String) async -> TipJarPurchaseOutcome {
        purchaseOutcomeByProductID[productID] ?? .failed(message: "Missing stub")
    }
}


