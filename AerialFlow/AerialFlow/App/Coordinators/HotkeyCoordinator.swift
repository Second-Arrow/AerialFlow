import Foundation
import KeyboardShortcuts

/// Owns hotkey handler registration. Call once during app startup.
final class HotkeyCoordinator: Sendable {
    private let binder: any HotkeyBinding

    init(binder: any HotkeyBinding) {
        self.binder = binder
    }

    struct Handlers: Sendable {
        let nextAerial: @Sendable () -> Void
        let nextInSubcategory: @Sendable () -> Void
        let excludeCurrentSubcategoryAndNext: @Sendable () -> Void
        let togglePause: @Sendable () -> Void
        let goToScreensaver: @Sendable () -> Void
    }

    func bind(_ handlers: Handlers) {
        binder.onKeyUp(for: .nextAerial, action: handlers.nextAerial)
        binder.onKeyUp(for: .nextInSubcategory, action: handlers.nextInSubcategory)
        binder.onKeyUp(for: .excludeCurrentSubcategoryAndNext, action: handlers.excludeCurrentSubcategoryAndNext)
        binder.onKeyUp(for: .togglePause, action: handlers.togglePause)
        binder.onKeyUp(for: .goToScreensaver, action: handlers.goToScreensaver)
    }
}

