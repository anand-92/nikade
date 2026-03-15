import AppKit
import SwiftUI

/// NSWindow 引用捕获器，用于配置原生窗口属性（titlebar、toolbar 等）。
/// 使用 viewDidMoveToWindow() 确保 window 可用时再执行配置。
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
