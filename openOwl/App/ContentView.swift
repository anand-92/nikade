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
            .background(AppPalette.base)
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
    @Namespace private var tabNamespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ViewTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        activeTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 10))
                            Text(tab.title)
                                .font(.system(size: 12, weight: activeTab == tab ? .semibold : .regular))
                        }
                        .foregroundStyle(activeTab == tab ? .primary : .secondary)

                        if activeTab == tab {
                            Capsule()
                                .fill(AppPalette.accent)
                                .frame(height: 2)
                                .matchedGeometryEffect(id: "indicator", in: tabNamespace)
                        } else {
                            Color.clear.frame(height: 2)
                        }
                    }
                    .fixedSize()
                    .padding(.horizontal, 10)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

