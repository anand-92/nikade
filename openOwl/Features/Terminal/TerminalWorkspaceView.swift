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

    @EnvironmentObject private var workspace: TerminalWorkspaceStore

    var body: some View {
        TerminalSplitNodeView(ghosttyApp: ghosttyApp, node: tab.splitTree, tabID: tab.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SplitDividerView: View {
    let axis: TerminalSplitAxis
    let hitAreaThickness: CGFloat

    @State private var isHovered = false

    var body: some View {
        let isHorizontal = axis == .horizontal

        ZStack {
            // Hit area (invisible, wider for easier grabbing)
            Rectangle()
                .fill(Color.clear)
                .frame(
                    width: isHorizontal ? hitAreaThickness : nil,
                    height: isHorizontal ? nil : hitAreaThickness
                )
                .contentShape(Rectangle())

            // Visual line
            Rectangle()
                .fill(isHovered ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.3))
                .frame(
                    width: isHorizontal ? 1 : nil,
                    height: isHorizontal ? nil : 1
                )
        }
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.setCursor(for: axis)
            } else {
                NSCursor.arrow.set()
            }
        }
    }
}

private extension NSCursor {
    static func setCursor(for axis: TerminalSplitAxis) {
        switch axis {
        case .horizontal:
            NSCursor.resizeLeftRight.set()
        case .vertical:
            NSCursor.resizeUpDown.set()
        }
    }
}

private struct DropZoneHighlightView: View {
    let zone: PaneDropZone

    var body: some View {
        switch zone {
        case .left:
            HStack(spacing: 0) {
                Color.accentColor.opacity(0.2)
                Color.clear
            }
        case .right:
            HStack(spacing: 0) {
                Color.clear
                Color.accentColor.opacity(0.2)
            }
        case .top:
            VStack(spacing: 0) {
                Color.accentColor.opacity(0.2)
                Color.clear
            }
        case .bottom:
            VStack(spacing: 0) {
                Color.clear
                Color.accentColor.opacity(0.2)
            }
        case .center:
            Color.accentColor.opacity(0.15)
        }
    }
}

private struct PaneDragHandle: View {
    let paneID: UUID

    @State private var isHovered = false
    @EnvironmentObject private var workspace: TerminalWorkspaceStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(Color.secondary.opacity(isHovered ? 1 : 0.6))
                        .frame(width: 3, height: 3)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 12)
            .background(Color(nsColor: .underPageBackgroundColor))
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onDrag {
                workspace.draggingPaneID = paneID
                return NSItemProvider(object: paneID.uuidString as NSString)
            }

            // Bottom separator
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 1)
        }
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
            let isMultiPane = (workspace.tabs.first(where: { $0.id == tabID })?.splitTree.leafCount ?? 1) > 1

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
                if isMultiPane, !workspace.isFocusedPane(paneID, in: tabID) {
                    Color.black.opacity(0.15)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if workspace.dragOverPaneID == paneID, let zone = workspace.dropZone {
                    DropZoneHighlightView(zone: zone)
                        .allowsHitTesting(false)
                }
            }

        case .split(let axis, let ratio, let first, let second):
            let firstID = first.firstPaneID ?? UUID()
            let secondID = second.firstPaneID ?? UUID()

            GeometryReader { geometry in
                let isHorizontal = axis == .horizontal
                let totalSize = isHorizontal ? geometry.size.width : geometry.size.height
                let firstSize = max(totalSize * ratio - 0.5, 0)
                let secondSize = max(totalSize * (1 - ratio) - 0.5, 0)

                // Original proven layout — spacing: 1 is the visual divider line
                if isHorizontal {
                    HStack(spacing: 1) {
                        TerminalSplitNodeView(ghosttyApp: ghosttyApp, node: first, tabID: tabID)
                            .frame(width: firstSize)
                        TerminalSplitNodeView(ghosttyApp: ghosttyApp, node: second, tabID: tabID)
                            .frame(width: secondSize)
                    }
                } else {
                    VStack(spacing: 1) {
                        TerminalSplitNodeView(ghosttyApp: ghosttyApp, node: first, tabID: tabID)
                            .frame(height: firstSize)
                        TerminalSplitNodeView(ghosttyApp: ghosttyApp, node: second, tabID: tabID)
                            .frame(height: secondSize)
                    }
                }

                // Draggable divider overlay — doesn't affect terminal frame sizes
                SplitDividerView(axis: axis, hitAreaThickness: 6)
                    .frame(
                        width: isHorizontal ? 6 : geometry.size.width,
                        height: isHorizontal ? geometry.size.height : 6
                    )
                    .position(
                        x: isHorizontal ? totalSize * ratio : geometry.size.width / 2,
                        y: isHorizontal ? geometry.size.height / 2 : totalSize * ratio
                    )
                    .gesture(DragGesture()
                        .onChanged { value in
                            let delta = isHorizontal ? value.translation.width : value.translation.height
                            let newRatio = (totalSize * ratio + delta) / totalSize
                            workspace.updateSplitRatio(firstPaneID: firstID, secondPaneID: secondID, newRatio: newRatio)
                        }
                    )
                    .onTapGesture(count: 2) {
                        workspace.equalizeSplits()
                    }
            }
        }
    }
}
