import SwiftUI

struct ContentView: View {
    @EnvironmentObject var ghosttyManager: GhosttyAppManager

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .frame(minWidth: AppConstants.sidebarMinWidth)
        } detail: {
            if ghosttyManager.isReady {
                TerminalPanel(ghosttyApp: ghosttyManager.app!)
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
        }
        .navigationSplitViewStyle(.balanced)
    }
}
