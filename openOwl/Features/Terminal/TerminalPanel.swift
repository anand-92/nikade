import SwiftUI

/// Bridges TerminalNSView (AppKit) into the SwiftUI view hierarchy.
struct TerminalPanel: NSViewRepresentable {
    let ghosttyApp: ghostty_app_t
    let paneID: UUID
    var onFocus: (() -> Void)? = nil
    @EnvironmentObject var appManager: GhosttyAppManager

    func makeNSView(context: Context) -> TerminalNSView {
        // #region agent log
        debugLog("TerminalPanel.swift:makeNSView", "creating TerminalNSView", ["hypothesisId": "H9", "paneID": paneID.uuidString])
        // #endregion
        let view = TerminalNSView(ghosttyApp: ghosttyApp, paneID: paneID)
        view.appManager = appManager
        view.onFocus = onFocus
        // #region agent log
        debugLog("TerminalPanel.swift:makeNSView-done", "TerminalNSView created", ["hypothesisId": "H9", "paneID": paneID.uuidString])
        // #endregion
        return view
    }

    func updateNSView(_ nsView: TerminalNSView, context: Context) {
        nsView.appManager = appManager
        nsView.onFocus = onFocus
    }
}
