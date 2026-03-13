import SwiftUI

struct ContentView: View {
    @EnvironmentObject var ghosttyManager: GhosttyAppManager
    @EnvironmentObject var navigationStore: AppNavigationStore

    var body: some View {
        // #region agent log
        let _ = debugLog("ContentView.swift:body", "ContentView.body evaluated", ["hypothesisId": "H4,H5", "isReady": ghosttyManager.isReady, "appNil": ghosttyManager.app == nil, "selection": navigationStore.selection?.rawValue ?? "nil"])
        // #endregion
        NavigationSplitView {
            SidebarView()
                .frame(minWidth: AppConstants.sidebarMinWidth)
        } detail: {
            switch navigationStore.selection ?? .terminal {
            case .terminal:
                if ghosttyManager.isReady {
                    TerminalWorkspaceView(ghosttyApp: ghosttyManager.app!)
                } else if let error = ghosttyManager.error {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Terminal initialization failed")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView("Initializing terminal...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

            case .gitChanges:
                GitChangesView()

            case .fileExplorer:
                FileExplorerView()
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}
