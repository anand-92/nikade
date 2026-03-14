import AppKit
import SwiftUI

struct TerminalWorkspaceView: View {
    let ghosttyApp: ghostty_app_t

    @EnvironmentObject private var workspace: TerminalWorkspaceStore
    @EnvironmentObject private var ghosttyManager: GhosttyAppManager

    var body: some View {
        VStack(spacing: 0) {
            TerminalTabBarView()

            ZStack {
                ForEach(workspace.tabs) { tab in
                    TerminalTabContentView(ghosttyApp: ghosttyApp, tab: tab)
                        .opacity(workspace.activeTabID == tab.id ? 1 : 0)
                        .allowsHitTesting(workspace.activeTabID == tab.id)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            workspace.focusPaneHandler = { [weak ghosttyManager] paneID in
                DispatchQueue.main.async {
                    _ = ghosttyManager?.focusPane(paneID)
                }
            }
            workspace.ensureInitialTab()
            focusCurrentPaneIfPossible()
        }
        .onChange(of: workspace.activeTabID) { _, _ in
            focusCurrentPaneIfPossible()
        }
    }

    private func focusCurrentPaneIfPossible() {
        guard let activeTabID = workspace.activeTabID else { return }
        guard let tab = workspace.tabs.first(where: { $0.id == activeTabID }) else { return }
        guard let paneID = tab.focusedPaneID ?? tab.splitTree.firstPaneID else { return }

        DispatchQueue.main.async {
            _ = ghosttyManager.focusPane(paneID)
        }
    }
}

private struct TerminalTabBarView: View {
    @EnvironmentObject private var workspace: TerminalWorkspaceStore

    private var hasMultipleTabs: Bool { workspace.tabs.count > 1 }

    var body: some View {
        HStack(spacing: 0) {
            // Tab 列表
            ForEach(Array(workspace.tabs.enumerated()), id: \.element.id) { index, tab in
                HStack(spacing: 4) {
                    Button {
                        workspace.selectTab(index: index)
                    } label: {
                        HStack(spacing: 3) {
                            Text(tab.title)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)

                            // ⌘N 快捷键标签
                            if index < 9 {
                                Text("⌘\(index + 1)")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    // 关闭按钮：仅多 tab 时显示
                    if hasMultipleTabs {
                        Button {
                            workspace.selectTab(index: index)
                            if workspace.closeCurrent() == .closeWindow {
                                NSApp.keyWindow?.performClose(nil)
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .opacity(0.5)
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: AppConstants.terminalToolbarHeight)
                .background(workspace.activeTabID == tab.id ? Color(nsColor: .windowBackgroundColor) : Color.clear)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(workspace.activeTabID == tab.id ? Color.accentColor : Color.clear)
                        .frame(height: 2)
                }
            }

            // 新 tab 按钮（紧贴 tab 列表右侧）
            Button {
                workspace.newTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 20, height: AppConstants.terminalToolbarHeight)
            }
            .buttonStyle(.plain)
            .opacity(0.7)

            Spacer(minLength: 8)

            // 右侧：分屏按钮
            HStack(spacing: 4) {
                Button {
                    workspace.splitCurrent(axis: .horizontal)
                } label: {
                    Image(systemName: "rectangle.split.1x2")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Split horizontally (⌘D)")

                Button {
                    workspace.splitCurrent(axis: .vertical)
                } label: {
                    Image(systemName: "rectangle.split.2x1")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Split vertically (⇧⌘D)")

                // Pane 数量标签
                if let tab = workspace.tabs.first(where: { $0.id == workspace.activeTabID }),
                   tab.splitTree.leafCount > 1 {
                    Text("\(tab.splitTree.leafCount)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.trailing, 8)
        }
        .frame(height: AppConstants.terminalToolbarHeight)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

private struct TerminalTabContentView: View {
    let ghosttyApp: ghostty_app_t
    let tab: TerminalTabState

    var body: some View {
        TerminalSplitNodeView(ghosttyApp: ghosttyApp, node: tab.splitTree, tabID: tab.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TerminalSplitNodeView: View {
    let ghosttyApp: ghostty_app_t
    let node: TerminalSplitNode
    let tabID: UUID

    @EnvironmentObject private var workspace: TerminalWorkspaceStore

    var body: some View {
        switch node {
        case .leaf(let paneID):
            TerminalPanel(
                ghosttyApp: ghosttyApp,
                paneID: paneID,
                onFocus: {
                    DispatchQueue.main.async {
                        workspace.focusPane(paneID)
                    }
                }
            )
            .overlay {
                // Only show focus ring when there are multiple panes
                if let tab = workspace.tabs.first(where: { $0.id == tabID }),
                   tab.splitTree.leafCount > 1,
                   workspace.isFocusedPane(paneID, in: tabID) {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
                        .padding(0.5)
                }
            }

        case .split(let axis, let ratio, let first, let second):
            GeometryReader { geometry in
                switch axis {
                case .horizontal:
                    HStack(spacing: 1) {
                        TerminalSplitNodeView(ghosttyApp: ghosttyApp, node: first, tabID: tabID)
                            .frame(width: max(geometry.size.width * ratio - 0.5, 0))
                        TerminalSplitNodeView(ghosttyApp: ghosttyApp, node: second, tabID: tabID)
                            .frame(width: max(geometry.size.width * (1 - ratio) - 0.5, 0))
                    }

                case .vertical:
                    VStack(spacing: 1) {
                        TerminalSplitNodeView(ghosttyApp: ghosttyApp, node: first, tabID: tabID)
                            .frame(height: max(geometry.size.height * ratio - 0.5, 0))
                        TerminalSplitNodeView(ghosttyApp: ghosttyApp, node: second, tabID: tabID)
                            .frame(height: max(geometry.size.height * (1 - ratio) - 0.5, 0))
                    }
                }
            }
        }
    }
}
