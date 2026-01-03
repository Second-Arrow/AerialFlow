import SwiftUI

struct TipJarView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: TipJarViewModel

    init(purchaser: any TipJarPurchasing, productIDs: [String]) {
        _model = StateObject(wrappedValue: TipJarViewModel(purchaser: purchaser, productIDs: productIDs))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Support Development")
                    .font(.headline)
                Text("AerialFlow is free. Tips are optional and don’t unlock features. Payments are processed by Apple.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if model.isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading tips…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if model.products.isEmpty {
                Text("No tips are available right now.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.products) { product in
                        Button {
                            Task { await model.purchase(productID: product.id) }
                        } label: {
                            HStack {
                                Text(product.displayName)
                                Spacer()
                                Text(product.displayPrice)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Text("Consumable purchases can’t be restored.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let info = model.infoMessage {
                Text(info)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let error = model.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Color.red)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 420, height: 320)
        .task {
            await model.loadProducts()
        }
    }
}


