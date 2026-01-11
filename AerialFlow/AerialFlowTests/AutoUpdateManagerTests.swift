import XCTest
import Sparkle
@testable import AerialFlow

final class AutoUpdateManagerTests: XCTestCase {
    func test_feedURLString_isExpected() {
        let sut = AutoUpdateManager(startingUpdater: false)
        XCTAssertEqual(sut.feedURLString(for: sut.controller.updater), Constants.sparkleFeedURLString)
    }

    func test_feedURLString_isValidHTTPSURL() {
        let sut = AutoUpdateManager(startingUpdater: false)
        let urlString = sut.feedURLString(for: sut.controller.updater)
        let url = urlString.flatMap(URL.init(string:))
        XCTAssertEqual(url?.scheme, "https")
        XCTAssertNotNil(url?.host)
    }
}

