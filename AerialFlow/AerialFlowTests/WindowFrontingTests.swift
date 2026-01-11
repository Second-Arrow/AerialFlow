import AppKit
import XCTest

@testable import AerialFlow

final class WindowFrontingTests: XCTestCase {
    func test_configure_insertsMoveToActiveSpaceAndFullScreenAuxiliary() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        WindowFronting.configure(window: window)

        XCTAssertTrue(window.collectionBehavior.contains(.moveToActiveSpace))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary))
    }

    func test_configure_preservesExistingCollectionBehavior() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.collectionBehavior = [.canJoinAllSpaces]

        WindowFronting.configure(window: window)

        XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces))
        // AppKit does not allow `.canJoinAllSpaces` and `.moveToActiveSpace` together.
        XCTAssertFalse(window.collectionBehavior.contains(.moveToActiveSpace))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary))
    }
}

