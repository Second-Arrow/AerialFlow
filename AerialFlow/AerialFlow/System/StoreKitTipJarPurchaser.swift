import Foundation
import StoreKit
import os

/// StoreKit 2 implementation for the consumable “Tip Jar”.
struct StoreKitTipJarPurchaser: TipJarPurchasing {
    private let logger = Logger(subsystem: Constants.loggerSubsystem, category: "TipJar")

    private let sortKeyByProductID: [String: Int] = [
        "com.secondarrow.AerialFlow.tip.small": 0,
        "com.secondarrow.AerialFlow.tip.coffee": 1,
        "com.secondarrow.AerialFlow.tip.lunch": 2,
        "com.secondarrow.AerialFlow.tip.bigThanks": 3
    ]

    func fetchProducts(productIDs: [String]) async throws -> [TipJarProduct] {
        let products = try await Product.products(for: productIDs)
        return products
            .map { product in
                TipJarProduct(
                    id: product.id,
                    displayName: product.displayName,
                    displayPrice: product.displayPrice,
                    sortKey: sortKeyByProductID[product.id] ?? Int.max
                )
            }
            .sorted { $0.sortKey < $1.sortKey }
    }

    func purchase(productID: String) async -> TipJarPurchaseOutcome {
        do {
            let products = try await Product.products(for: [productID])
            guard let product = products.first else {
                return .failed(message: "This product isn’t available right now.")
            }

            let result = try await product.purchase()

            switch result {
            case .success(let verificationResult):
                switch verificationResult {
                case .verified(let transaction):
                    await transaction.finish()
                    return .success
                case .unverified(_, let error):
                    logger.error("Unverified tip transaction: \(String(describing: error), privacy: .public)")
                    return .failed(message: "Purchase couldn’t be verified.")
                }
            case .userCancelled:
                return .userCancelled
            case .pending:
                return .pending
            @unknown default:
                return .failed(message: "Purchase failed.")
            }
        } catch {
            logger.error("Tip purchase failed: \(String(describing: error), privacy: .public)")
            return .failed(message: error.localizedDescription)
        }
    }
}


