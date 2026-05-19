import AppKit
import SwiftUI

/// NSWindow reference capturer, used to configure native window properties (titlebar, toolbar, etc.).
/// Uses viewDidMoveToWindow() to ensure window is available before configuration.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowAccessorNSView {
        let view = WindowAccessorNSView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: WindowAccessorNSView, context: Context) {}
}

class WindowAccessorNSView: NSView {
    var onWindow: ((NSWindow) -> Void)?
    private var configured = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !configured, let window else { return }
        configured = true
        onWindow?(window)
    }
}
