import AppKit
import SwiftUI

struct TerminalWorkspaceView: View {
    let ghosttyApp: ghostty_app_t

    @EnvironmentObject private var workspace: TerminalWorkspaceStore
    @EnvironmentObject private var ghosttyManager: GhosttyAppManager
    @State private var activatedTabIDs: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            TerminalTabBarView()

            ZStack {
                // Lazy: only render tabs that have been activated at least once
                // Once rendered, keep alive forever (opacity hide, never removed from tree)
                ForEach(workspace.tabs.filter { activatedTabIDs.contains($0.id) }) { tab in
                    let isActive = workspace.activeTabID == tab.id && workspace.isTabVisible(tab.id)
                    TerminalTabContentView(ghosttyApp: ghosttyApp, tab: tab)
                        .opacity(isActive ? 1 : 0)
                        .allowsHitTesting(isActive)
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
            activateVisibleTabs()
            focusCurrentPaneIfPossible()
        }
        .onChange(of: workspace.activeTabID) { _, _ in
            activateVisibleTabs()
            focusCurrentPaneIfPossible()
        }
        .onChange(of: workspace.activeProjectID) { _, _ in
            activateVisibleTabs()
        }
    }

    private func activateVisibleTabs() {
        for tab in workspace.visibleTabs {
            activatedTabIDs.insert(tab.id)
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
    @State private var hoveredTabID: UUID?

    private var displayTabs: [TerminalTabState] { workspace.visibleTabs }
    private var hasMultipleTabs: Bool { displayTabs.count > 1 }

    var body: some View {
        HStack(spacing: 0) {
            // Tab 列表 (only current project's tabs)
            ForEach(Array(displayTabs.enumerated()), id: \.element.id) { index, tab in
                let isActive = workspace.activeTabID == tab.id
                let isHovered = hoveredTabID == tab.id

                HStack(spacing: 4) {
                    Button {
                        workspace.activeTabID = tab.id
                    } label: {
                        HStack(spacing: 3) {
                            Text(tab.title)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)

                            // ⌘N 快捷键标签
                            if index < 9 {
                                Text("⌘\(index + 1)")
                                    .font(AppFonts.badge)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    // 关闭按钮：仅多 tab 时显示
                    if hasMultipleTabs {
                        Button {
                            workspace.activeTabID = tab.id
                            if workspace.closeCurrent() == .closeWindow {
                                NSApp.keyWindow?.performClose(nil)
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .opacity(isHovered ? 1.0 : 0.7)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: AppSpacing.cornerRadius)
                        .fill(
                            isActive
                                ? AppColors.activeBackground
                                : (isHovered ? AppColors.hoverBackground : Color.clear)
                        )
                )
                .onHover { hoveredTabID = $0 ? tab.id : nil }

                // Tab 分隔线
                if index < displayTabs.count - 1 {
                    TerminalTabDivider()
                }
            }

            // 新 tab 按钮（紧贴 tab 列表右侧）
            Button {
                workspace.newTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 20, height: AppSpacing.headerHeight)
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
                        .font(AppFonts.badge)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.trailing, 8)
        }
        .padding(.horizontal, 4)
        .frame(height: AppSpacing.headerHeight)
        .background(Color(nsColor: .underPageBackgroundColor))
        .animation(.easeInOut(duration: 0.15), value: workspace.activeTabID)
    }
}

// MARK: - Terminal Tab Divider

private struct TerminalTabDivider: View {
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

/// Flat layout: all panes are positioned absolutely within a GeometryReader.
/// This prevents SwiftUI from destroying/recreating terminal views when the
/// split tree structure changes (add/remove/move splits).
private struct TerminalTabContentView: View {
    let ghosttyApp: ghostty_app_t
    let tab: TerminalTabState

    @EnvironmentObject private var workspace: TerminalWorkspaceStore
    @State private var dividerDragStart: [String: Double] = [:]

    var body: some View {
        let paneIDs = tab.splitTree.allPaneIDs
        let isMultiPane = paneIDs.count > 1

        GeometryReader { geometry in
            let _ = clearStaleDragState(dividers: tab.splitTree.dividerInfos(in: CGRect(origin: .zero, size: geometry.size)))
            let size = geometry.size
            let bounds = CGRect(origin: .zero, size: size)
            let frames = tab.splitTree.paneFrames(in: bounds)
            let dividers = tab.splitTree.dividerInfos(in: bounds)

            ZStack(alignment: .topLeading) {
                // All terminal panes with absolute positioning
                ForEach(paneIDs, id: \.self) { paneID in
                    let frame = frames[paneID] ?? .zero

                    VStack(spacing: 0) {
                        if isMultiPane {
                            PaneDragHandle(paneID: paneID)
                        }

                        TerminalPanel(
                            ghosttyApp: ghosttyApp,
                            paneID: paneID,
                            onFocus: {
                                DispatchQueue.main.async {
                                    workspace.focusPane(paneID)
                                }
                            }
                        )
                    }
                    .frame(width: max(frame.width, 1), height: max(frame.height, 1))
                    .contentShape(Rectangle())
                    .clipped()
                    .overlay {
                        // 非聚焦 pane 遮罩（轻柔）
                        if isMultiPane, !workspace.isFocusedPane(paneID, in: tab.id) {
                            Color.black.opacity(0.06)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay {
                        if workspace.dragOverPaneID == paneID, let zone = workspace.dropZone {
                            DropZoneHighlightView(zone: zone)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay {
                        Color.clear
                            .contentShape(Rectangle())
                            .onDrop(of: [.text], delegate: PaneDropDelegate(
                                targetPaneID: paneID,
                                workspace: workspace,
                                viewSize: frame.size
                            ))
                            .allowsHitTesting(workspace.draggingPaneID != nil && workspace.draggingPaneID != paneID)
                    }
                    .position(x: frame.midX, y: frame.midY)
                    .zIndex(0)
                }

                // Dividers
                ForEach(dividers) { divider in
                    let isH = divider.axis == .horizontal
                    SplitDividerView(axis: divider.axis, hitAreaThickness: 6)
                        .frame(
                            width: isH ? 6 : divider.frame.width,
                            height: isH ? divider.frame.height : 6
                        )
                        .position(x: divider.frame.midX, y: divider.frame.midY)
                        .zIndex(1)
                        .gesture(DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                if dividerDragStart[divider.id] == nil {
                                    dividerDragStart[divider.id] = divider.ratio
                                }
                                let baseRatio = dividerDragStart[divider.id] ?? divider.ratio
                                let totalSize = isH ? size.width : size.height
                                let delta = isH ? value.translation.width : value.translation.height
                                workspace.updateSplitRatio(
                                    firstPaneID: divider.firstPaneID,
                                    secondPaneID: divider.secondPaneID,
                                    newRatio: baseRatio + delta / totalSize
                                )
                            }
                            .onEnded { _ in
                                dividerDragStart.removeValue(forKey: divider.id)
                            }
                        )
                        .onTapGesture(count: 2) {
                            workspace.equalizeSplits()
                        }
                }
            }
        }
    }

    /// Remove drag-start entries for dividers that no longer exist (tree changed mid-drag)
    private func clearStaleDragState(dividers: [SplitDividerInfo]) {
        let validIDs = Set(dividers.map(\.id))
        for key in dividerDragStart.keys where !validIDs.contains(key) {
            dividerDragStart.removeValue(forKey: key)
        }
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
                dropZoneContent
                Color.clear
            }
        case .right:
            HStack(spacing: 0) {
                Color.clear
                dropZoneContent
            }
        case .top:
            VStack(spacing: 0) {
                dropZoneContent
                Color.clear
            }
        case .bottom:
            VStack(spacing: 0) {
                Color.clear
                dropZoneContent
            }
        case .center:
            Color.accentColor.opacity(0.15)
        }
    }

    private var dropZoneContent: some View {
        Color.accentColor.opacity(0.2)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.accentColor.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .padding(4)
            )
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

// Old recursive TerminalSplitNodeView and SplitContainerView removed.
// Replaced by flat layout in TerminalTabContentView above.

// MARK: - Pane Drop Delegate

private struct PaneDropDelegate: DropDelegate {
    let targetPaneID: UUID
    let workspace: TerminalWorkspaceStore
    let viewSize: CGSize

    func dropEntered(info: DropInfo) {
        workspace.dragOverPaneID = targetPaneID
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard workspace.draggingPaneID != nil,
              workspace.draggingPaneID != targetPaneID else {
            return DropProposal(operation: .cancel)
        }

        workspace.dragOverPaneID = targetPaneID
        workspace.dropZone = detectZone(at: info.location)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if workspace.dragOverPaneID == targetPaneID {
            workspace.dragOverPaneID = nil
            workspace.dropZone = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let sourceID = workspace.draggingPaneID,
              sourceID != targetPaneID else {
            cleanup()
            return false
        }

        let zone = workspace.dropZone ?? .center
        workspace.movePaneToTarget(sourceID: sourceID, targetID: targetPaneID, zone: zone)
        cleanup()
        return true
    }

    /// Detect drop zone based on cursor position within the target pane.
    /// Edges (30% inset) → directional split. Center → swap.
    private func detectZone(at point: CGPoint) -> PaneDropZone {
        let w = viewSize.width
        let h = viewSize.height
        guard w > 0, h > 0 else { return .center }

        let relX = point.x / w  // 0..1
        let relY = point.y / h  // 0..1
        let edgeThreshold: CGFloat = 0.3

        // Check edges first
        if relX < edgeThreshold { return .left }
        if relX > 1 - edgeThreshold { return .right }
        if relY < edgeThreshold { return .top }
        if relY > 1 - edgeThreshold { return .bottom }

        return .center
    }

    private func cleanup() {
        workspace.draggingPaneID = nil
        workspace.dragOverPaneID = nil
        workspace.dropZone = nil
    }
}
