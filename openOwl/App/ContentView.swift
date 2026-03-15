import SwiftUI

struct ContentView: View {
    @EnvironmentObject var ghosttyManager: GhosttyAppManager
    @EnvironmentObject var navigationStore: AppNavigationStore

    @State private var sidebarWidth: CGFloat = AppConstants.sidebarWidth
    @State private var sidebarCollapsed = false
    @State private var sidebarDragDelta: CGFloat? = nil

    /// Width before collapse, for restore
    @State private var sidebarWidthBeforeCollapse: CGFloat = AppConstants.sidebarWidth

    var body: some View {
        ZStack(alignment: .leading) {
            // Main layout
            HStack(spacing: 0) {
                if !sidebarCollapsed {
                    SidebarView(onToggleCollapse: { toggleSidebar() })
                        .frame(width: sidebarWidth)
                }

                SidebarDivider(
                    collapsed: sidebarCollapsed,
                    onToggle: { toggleSidebar() }
                )
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { value in
                            sidebarDragDelta = value.translation.width
                        }
                        .onEnded { value in
                            let newWidth = sidebarWidth + value.translation.width
                            if newWidth < 80 {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    sidebarCollapsed = true
                                }
                            } else {
                                sidebarWidth = min(max(newWidth, 140), 500)
                            }
                            sidebarDragDelta = nil
                        }
                )

                // 右面板
                VStack(spacing: 0) {
                    ViewTabBar(activeTab: $navigationStore.activeTab)

                    Divider()

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

            // Drag indicator line — lightweight overlay, no sidebar re-render
            if let delta = sidebarDragDelta, !sidebarCollapsed {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(width: 2)
                    .offset(x: min(max(sidebarWidth + delta, 140), 500) - 1)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: sidebarCollapsed)
    }

    private func toggleSidebar() {
        if sidebarCollapsed {
            sidebarCollapsed = false
            sidebarWidth = sidebarWidthBeforeCollapse
        } else {
            sidebarWidthBeforeCollapse = sidebarWidth
            sidebarCollapsed = true
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

// MARK: - Sidebar Divider

private struct SidebarDivider: View {
    let collapsed: Bool
    let onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(isHovered ? Color.accentColor.opacity(0.4) : Color(nsColor: .separatorColor))
                .frame(width: isHovered ? 3 : 1)

            // Collapse/expand arrow button shown on hover
            if isHovered {
                Button(action: onToggle) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 36)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 7)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
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
