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
            // #region agent log
            debugLog("TerminalWorkspaceView.swift:onAppear-start", "TerminalWorkspaceView onAppear", ["hypothesisId": "H8", "tabCount": workspace.tabs.count])
            // #endregion
            workspace.focusPaneHandler = { [weak ghosttyManager] paneID in
                DispatchQueue.main.async {
                    _ = ghosttyManager?.focusPane(paneID)
                }
            }
            workspace.ensureInitialTab()
            // #region agent log
            debugLog("TerminalWorkspaceView.swift:onAppear-after-tab", "ensureInitialTab done", ["hypothesisId": "H8", "tabCount": workspace.tabs.count, "activeTabID": workspace.activeTabID?.uuidString ?? "nil"])
            // #endregion
            focusCurrentPaneIfPossible()
            // #region agent log
            debugLog("TerminalWorkspaceView.swift:onAppear-done", "TerminalWorkspaceView onAppear completed", ["hypothesisId": "H8"])
            // #endregion
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

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(workspace.tabs.enumerated()), id: \.element.id) { index, tab in
                HStack(spacing: 6) {
                    Button {
                        workspace.selectTab(index: index)
                    } label: {
                        Text(tab.title)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)

                    Button {
                        workspace.selectTab(index: index)
                        if workspace.closeCurrent() == .closeWindow {
                            NSApp.keyWindow?.performClose(nil)
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .opacity(0.7)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(workspace.activeTabID == tab.id ? Color(nsColor: .windowBackgroundColor) : Color.clear)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(workspace.activeTabID == tab.id ? Color.accentColor : Color.clear)
                        .frame(height: 2)
                }
            }

            Spacer(minLength: 8)

            Button {
                workspace.newTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(6)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
        }
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
                if workspace.isFocusedPane(paneID, in: tabID) {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.accentColor.opacity(0.75), lineWidth: 1)
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
