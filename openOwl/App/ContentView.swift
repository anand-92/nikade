import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(GhosttyAppManager.self) var ghosttyManager
    @Environment(AppNavigationStore.self) var navigationStore
    @Environment(FileExplorerStore.self) var fileExplorerStore
    @Environment(DeploymentStore.self) var deploymentStore
    @Environment(ProjectStore.self) var projectStore
    @Environment(RightDockStore.self) var rightDockStore

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 250, max: 500)
        } detail: {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        // Terminal — center area. Hidden when the right dock is
                        // fullscreen but kept mounted (no surface destroy) so its
                        // shell processes keep running in the background.
                        terminalContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .frame(width: rightDockStore.isFullscreen ? 0 : nil)
                            .clipped()

                        if rightDockStore.isExpanded {
                            Divider()

                            RightDockView(hostWidth: geo.size.width)
                                .frame(
                                    width: rightDockStore.isFullscreen
                                        ? max(0, geo.size.width)
                                        : rightDockStore.width
                                )
                                .frame(maxHeight: .infinity)
                        }
                    }

                    Divider()

                    StatusBarView()
                }
                .background(AppPalette.base)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            if !rightDockStore.isExpanded {
                ToolbarItemGroup(placement: .primaryAction) {
                    RightDockToolbarButtons()
                }
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
            navigationStore.openDeployment(
                id: id,
                deploymentStore: deploymentStore,
                projectStore: projectStore,
                rightDockStore: rightDockStore
            )
        }
        .onChange(of: rightDockStore.activeTab) { _, _ in
            resignFirstResponderForTabSwitch()
        }
        .onChange(of: rightDockStore.isExpanded) { _, _ in
            resignFirstResponderForTabSwitch()
        }
    }

    @ViewBuilder
    private var terminalContent: some View {
        if ghosttyManager.isReady {
            TerminalWorkspaceView(
                ghosttyApp: ghosttyManager.app!,
                isVisible: !rightDockStore.isFullscreen
            )
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

    @MainActor
    private func resignFirstResponderForTabSwitch() {
        guard let window = NSApp.keyWindow else { return }
        window.endEditing(for: nil)
        window.makeFirstResponder(nil)
    }
}

// MARK: - Right Dock Toolbar Buttons

/// Three toggle buttons for the right dock (Files / Git / Deploy).
/// Tap behavior is delegated to RightDockStore.toggle(tab:).
private struct RightDockToolbarButtons: View {
    @Environment(RightDockStore.self) private var rightDockStore

    var body: some View {
        HStack(spacing: 2) {
            ForEach(RightDockTab.allCases) { tab in
                let isActive = rightDockStore.isExpanded && rightDockStore.activeTab == tab
                Button {
                    rightDockStore.toggle(tab: tab)
                } label: {
                    Image(systemName: tab.systemImage)
                        .font(AppFonts.toolbarIcon)
                        .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(.plain)
                .help(tab.title)
                .accessibilityLabel(tab.title)
                .keyboardShortcut(shortcutKey(for: tab), modifiers: [.command])
            }
        }
    }

    private func shortcutKey(for tab: RightDockTab) -> KeyEquivalent {
        switch tab {
        case .files: return "1"
        case .git: return "2"
        case .deploy: return "3"
        }
    }
}
