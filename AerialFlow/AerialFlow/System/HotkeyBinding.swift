import Foundation
import KeyboardShortcuts

protocol HotkeyBinding: Sendable {
    func onKeyUp(for name: KeyboardShortcuts.Name, action: @escaping @Sendable () -> Void)
}

struct KeyboardShortcutsHotkeyBinder: HotkeyBinding {
    init() {}

    func onKeyUp(for name: KeyboardShortcuts.Name, action: @escaping @Sendable () -> Void) {
        KeyboardShortcuts.onKeyUp(for: name, action: action)
    }
}


