import SwiftUI

struct ContentView: View {
    @EnvironmentObject var ghosttyManager: GhosttyAppManager
    @EnvironmentObject var navigationStore: AppNavigationStore
    @EnvironmentObject var fileExplorerStore: FileExplorerStore
    @EnvironmentObject var deploymentStore: DeploymentStore
    @EnvironmentObject var projectStore: ProjectStore

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 250, max: 500)
        } detail: {
            VStack(spacing: 0) {
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

                    if navigationStore.activeTab == .deployments {
                        DeploymentPanelView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                StatusBarView()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .principal) {
                ViewTabBar(activeTab: $navigationStore.activeTab)
            }
        }
        .navigationTitle("")
        .background {
            Button("") { fileExplorerStore.presentQuickOpen(projectURL: projectStore.activeProjectURL) }
                .keyboardShortcut("p", modifiers: [.command])
                .hidden()
        }
        .overlay {
            if fileExplorerStore.isQuickOpenPresented {
                ZStack(alignment: .top) {
                    // Click outside to dismiss
                    Color.black.opacity(0.001)
                        .onTapGesture { fileExplorerStore.dismissQuickOpen() }

                    QuickOpenPanel()
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                .zIndex(100)
            }
        }
        .animation(.easeOut(duration: 0.15), value: fileExplorerStore.isQuickOpenPresented)
        .onReceive(NotificationCenter.default.publisher(for: .quickOpen)) { _ in
            fileExplorerStore.presentQuickOpen(projectURL: projectStore.activeProjectURL)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openDeployment)) { notification in
            guard let id = notification.userInfo?["id"] as? String else { return }
            // Switch to the deployment's project
            if let dep = deploymentStore.deployments.first(where: { $0.id == id }) {
                projectStore.activateProject(id: dep.projectID)
            }
            navigationStore.activeTab = .deployments
            deploymentStore.selectedDeploymentID = id
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
    @State private var hoveredTab: ViewTab?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ViewTab.allCases) { tab in
                Button {
                    activeTab = tab
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 10))
                        Text(tab.title)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(activeTab == tab ? .primary : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(activeTab == tab ? Color.accentColor.opacity(0.15) : (hoveredTab == tab ? Color.secondary.opacity(0.1) : Color.clear))
                    )
                }
                .buttonStyle(.plain)
                .onHover { hoveredTab = $0 ? tab : nil }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: activeTab)
    }
}

// MARK: - Tab Divider

private struct TabDivider: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Rectangle()
            .frame(width: 1)
            .padding(.vertical, 8)
            .foregroundColor(
                colorScheme == .dark
                    ? Color.white.opacity(0.12)
                    : Color.black.opacity(0.12)
            )
    }
}
