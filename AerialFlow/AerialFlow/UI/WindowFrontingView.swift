import AppKit
import SwiftUI

struct WindowFrontingView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowFrontingNSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowFrontingNSView: NSView {
    private weak var lastWindow: NSWindow?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard let window else { return }
        guard window !== lastWindow else { return }
        lastWindow = window

        WindowFronting.configure(window: window)
    }
}

