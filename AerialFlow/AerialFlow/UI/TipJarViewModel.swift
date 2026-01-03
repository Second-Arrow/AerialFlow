import Combine
import Foundation
import os

@MainActor
final class TipJarViewModel: ObservableObject {
    private let logger = Logger(subsystem: Constants.loggerSubsystem, category: "TipJarViewModel")

    private let purchaser: any TipJarPurchasing
    private let productIDs: [String]

    @Published private(set) var products: [TipJarProduct] = []
    @Published private(set) var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var infoMessage: String?

    init(purchaser: any TipJarPurchasing, productIDs: [String]) {
        self.purchaser = purchaser
        self.productIDs = productIDs
    }

    func loadProducts() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let loaded = try await purchaser.fetchProducts(productIDs: productIDs)
            products = loaded.sorted { $0.sortKey < $1.sortKey }
            errorMessage = nil
        } catch {
            logger.error("Failed to load tip jar products: \(String(describing: error), privacy: .public)")
            products = []
            errorMessage = "Couldn’t load tips right now. Please try again later."
        }
    }

    func purchase(productID: String) async {
        errorMessage = nil
        infoMessage = nil

        let outcome = await purchaser.purchase(productID: productID)
        switch outcome {
        case .success:
            infoMessage = "Thank you for supporting AerialFlow."
        case .pending:
            infoMessage = "Your purchase is pending approval."
        case .userCancelled:
            infoMessage = "Purchase cancelled."
        case .failed(let message):
            errorMessage = message
        }
    }
}


