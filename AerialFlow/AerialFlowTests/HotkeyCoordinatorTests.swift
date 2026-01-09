import Foundation
import Testing
import KeyboardShortcuts
@testable import AerialFlow

private final class CapturingHotkeyBinder: HotkeyBinding, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var registeredNames: [KeyboardShortcuts.Name] = []

    func onKeyUp(for name: KeyboardShortcuts.Name, action: @escaping @Sendable () -> Void) {
        _ = action
        lock.lock()
        registeredNames.append(name)
        lock.unlock()
    }
}

struct HotkeyCoordinatorTests {
    @Test func testBind_registersAllExpectedHotkeys() async {
        let binder = CapturingHotkeyBinder()
        let coordinator = HotkeyCoordinator(binder: binder)

        coordinator.bind(.init(
            nextAerial: {},
            nextInSubcategory: {},
            excludeCurrentSubcategoryAndNext: {},
            togglePause: {},
            goToScreensaver: {}
        ))

        let names = Set(binder.registeredNames)
        #expect(names.contains(.nextAerial))
        #expect(names.contains(.nextInSubcategory))
        #expect(names.contains(.excludeCurrentSubcategoryAndNext))
        #expect(names.contains(.togglePause))
        #expect(names.contains(.goToScreensaver))
        #expect(names.count == 5)
    }
}

