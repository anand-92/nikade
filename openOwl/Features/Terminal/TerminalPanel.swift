import SwiftUI

/// Bridges TerminalNSView (AppKit) into the SwiftUI view hierarchy,
/// wrapped in a TerminalScrollView to provide native macOS scrollbar support.
struct TerminalPanel: NSViewRepresentable {
    let ghosttyApp: ghostty_app_t
    let paneID: UUID
    var onFocus: (() -> Void)? = nil
    @Environment(GhosttyAppManager.self) var appManager

    func makeNSView(context: Context) -> TerminalScrollView {
        // Reuse an existing TerminalNSView if SwiftUI dismantled a previous wrapper.
        // The surface stays alive inside the retained view — no terminal restart.
        let terminalView: TerminalNSView
        if let existing = appManager.terminalView(for: paneID) {
            terminalView = existing
            terminalView.onFocus = onFocus
        } else {
            terminalView = TerminalNSView(ghosttyApp: ghosttyApp, paneID: paneID)
            terminalView.appManager = appManager
            terminalView.onFocus = onFocus
        }

        let scrollView = TerminalScrollView(terminalView: terminalView)
        appManager.registerScrollView(scrollView, for: paneID)
        return scrollView
    }

    func updateNSView(_ nsView: TerminalScrollView, context: Context) {
        // No dynamic updates — the surface handles its own state.
    }
}
