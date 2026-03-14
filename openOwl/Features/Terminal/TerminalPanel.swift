import SwiftUI

/// Bridges TerminalNSView (AppKit) into the SwiftUI view hierarchy.
struct TerminalPanel: NSViewRepresentable {
    let ghosttyApp: ghostty_app_t
    let paneID: UUID
    var onFocus: (() -> Void)? = nil
    @EnvironmentObject var appManager: GhosttyAppManager

    func makeNSView(context: Context) -> TerminalNSView {
        let view = TerminalNSView(ghosttyApp: ghosttyApp, paneID: paneID)
        view.appManager = appManager
        view.onFocus = onFocus
        return view
    }

    func updateNSView(_ nsView: TerminalNSView, context: Context) {
        // No dynamic updates — the surface handles its own state.
    }
}
