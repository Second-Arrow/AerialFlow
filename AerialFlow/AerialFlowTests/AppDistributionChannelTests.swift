import XCTest
@testable import AerialFlow

final class AppDistributionChannelTests: XCTestCase {
    func testCurrent_whenReceiptExists_returnsAppStore() {
        let appBundleURL = URL(fileURLWithPath: "/Applications/AerialFlow.app")
        let channel = AppDistributionChannel.current(
            bundleURL: appBundleURL,
            fileExists: { url in
                url.path.hasSuffix("/Contents/_MASReceipt/receipt")
            }
        )
        XCTAssertEqual(channel, .appStore)
    }

    func testCurrent_whenReceiptMissing_returnsDirect() {
        let channel = AppDistributionChannel.current(
            bundleURL: URL(fileURLWithPath: "/Applications/AerialFlow.app"),
            fileExists: { _ in false }
        )
        XCTAssertEqual(channel, .direct)
    }
}


