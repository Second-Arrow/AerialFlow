import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let nextAerial = Self(
        "nextAerial",
        default: KeyboardShortcuts.Shortcut(.n, modifiers: [.command, .option])
    )

    static let togglePause = Self(
        "togglePause",
        default: KeyboardShortcuts.Shortcut(.p, modifiers: [.command, .option])
    )

    static let goToScreensaver = Self(
        "goToScreensaver",
        default: KeyboardShortcuts.Shortcut(.s, modifiers: [.command, .option])
    )
}


