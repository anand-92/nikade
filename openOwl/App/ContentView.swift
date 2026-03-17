import SwiftUI

struct ContentView: View {
    @Environment(GhosttyAppManager.self) var ghosttyManager
    @Environment(AppNavigationStore.self) var navigationStore
    @Environment(FileExplorerStore.self) var fileExplorerStore
    @Environment(DeploymentStore.self) var deploymentStore
    @Environment(ProjectStore.self) var projectStore

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var navigationStore = navigationStore
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
                        NavigationStack {
                            GitChangesView()
                        }
                    }

                    if navigationStore.activeTab == .fileExplorer {
                        NavigationStack {
                            FileExplorerView()
                        }
                    }

                    if navigationStore.activeTab == .deployments {
                        NavigationStack {
                            DeploymentPanelView()
                        }
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
            navigationStore.openDeployment(id: id, deploymentStore: deploymentStore, projectStore: projectStore)
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
                let isActive = activeTab == tab

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        activeTab = tab
                    }
                } label: {
                    tabLabel(tab, isActive: isActive)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func tabLabel(_ tab: ViewTab, isActive: Bool) -> some View {
        if #available(macOS 26, *) {
            HStack(spacing: 4) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 10))
                Text(tab.title)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
            }
            .foregroundStyle(isActive ? .primary : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .glassEffect(isActive ? .regular.tint(.accentColor) : .identity, in: .capsule)
        } else {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: tab.systemImage)
                        .font(.system(size: 10))
                    Text(tab.title)
                        .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                }
                .foregroundStyle(isActive ? .primary : .secondary)

                if isActive {
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
    }
}
