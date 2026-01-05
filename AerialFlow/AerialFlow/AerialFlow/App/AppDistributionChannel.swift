import Foundation

enum AppDistributionChannel: Equatable {
    case appStore
    case direct

    static func current(
        bundleURL: URL = Bundle.main.bundleURL,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> AppDistributionChannel {
        let receiptURL = bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("_MASReceipt", isDirectory: true)
            .appendingPathComponent("receipt", isDirectory: false)

        guard fileExists(receiptURL) else {
            return .direct
        }
        return .appStore
    }
}


