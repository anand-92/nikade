import SwiftUI

struct ContentView: View {
    @EnvironmentObject var ghosttyManager: GhosttyAppManager
    @EnvironmentObject var navigationStore: AppNavigationStore

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: AppConstants.sidebarWidth)

            Divider()

            // 右面板
            VStack(spacing: 0) {
                ViewTabBar(activeTab: $navigationStore.activeTab)

                Divider()

                // 内容区：Terminal 始终存在（opacity 切换），Git/Files 按需渲染
                ZStack {
                    terminalContent
                        .opacity(navigationStore.activeTab == .terminal ? 1 : 0)
                        .allowsHitTesting(navigationStore.activeTab == .terminal)

                    if navigationStore.activeTab == .gitChanges {
                        GitChangesView()
                    }

                    if navigationStore.activeTab == .fileExplorer {
                        FileExplorerView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private var terminalContent: some View {
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
    }
}

// MARK: - View Tab Bar

private struct ViewTabBar: View {
    @Binding var activeTab: ViewTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ViewTab.allCases) { tab in
                Button {
                    activeTab = tab
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 11))
                        Text(tab.title)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(activeTab == tab ? .primary : .secondary)
                    .padding(.horizontal, 12)
                    .frame(height: AppConstants.headerHeight)
                    .contentShape(Rectangle())
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(activeTab == tab ? Color.accentColor : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
