import SwiftUI

/// Bridges TerminalNSView (AppKit) into the SwiftUI view hierarchy.
struct TerminalPanel: NSViewRepresentable {
    let ghosttyApp: ghostty_app_t
    @EnvironmentObject var appManager: GhosttyAppManager

    func makeNSView(context: Context) -> TerminalNSView {
        let view = TerminalNSView(ghosttyApp: ghosttyApp)
        view.appManager = appManager
        return view
    }

    func updateNSView(_ nsView: TerminalNSView, context: Context) {
        // No dynamic updates needed — the surface handles its own state
    }
}
