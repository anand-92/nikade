import SwiftUI

/// Bridges TerminalNSView (AppKit) into the SwiftUI view hierarchy,
/// wrapped in a TerminalScrollView to provide native macOS scrollbar support.
struct TerminalPanel: NSViewRepresentable {
    let ghosttyApp: ghostty_app_t
    let paneID: UUID
    var onFocus: (() -> Void)? = nil
    @Environment(GhosttyAppManager.self) var appManager

    func makeNSView(context: Context) -> TerminalScrollView {
        let terminalView = TerminalNSView(ghosttyApp: ghosttyApp, paneID: paneID)
        terminalView.appManager = appManager
        terminalView.onFocus = onFocus

        let scrollView = TerminalScrollView(terminalView: terminalView)
        appManager.registerScrollView(scrollView, for: paneID)
        return scrollView
    }

    func updateNSView(_ nsView: TerminalScrollView, context: Context) {
        // No dynamic updates — the surface handles its own state.
    }
}
