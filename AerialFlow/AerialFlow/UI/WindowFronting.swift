import AppKit

enum WindowFronting {
    static func configure(window: NSWindow) {
        NSApplication.shared.activate(ignoringOtherApps: true)

        // AppKit constraint: `.canJoinAllSpaces` and `.moveToActiveSpace` are mutually exclusive
        // and will crash with `NSInternalInconsistencyException` if combined.
        var behavior = window.collectionBehavior
        behavior.insert(.fullScreenAuxiliary)
        if behavior.contains(.canJoinAllSpaces) {
            behavior.remove(.moveToActiveSpace)
        } else {
            behavior.insert(.moveToActiveSpace)
        }
        window.collectionBehavior = behavior

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
    }
}

