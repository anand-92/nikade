import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Private UTType for in-app pane rearrangement drag.
/// Using a dedicated type prevents TerminalScrollView (which accepts .string)
/// from intercepting pane drags, and allows the drop overlay to be
/// always-present without interfering with Finder file drops (.fileURL).
private let paneDragTypeID = "com.openowl.terminal.pane-drag"

struct TerminalWorkspaceView: View {
    let ghosttyApp: ghostty_app_t

    @Environment(TerminalWorkspaceStore.self) private var workspace
    @Environment(GhosttyAppManager.self) private var ghosttyManager
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
                        .transaction { $0.animation = nil }
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
            connectSearchCallbacks()
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
        .onReceive(NotificationCenter.default.publisher(for: .terminalSearch)) { notification in
            guard let paneID = notification.userInfo?["paneID"] as? UUID else { return }
            workspace.startSearch(paneID: paneID)
        }
    }

    private func activateVisibleTabs() {
        for tab in workspace.visibleTabs {
            activatedTabIDs.insert(tab.id)
        }
    }

    private func connectSearchCallbacks() {
        ghosttyManager.onSearchEnd = { [weak workspace] paneID in
            workspace?.endSearch(paneID: paneID)
        }
        ghosttyManager.onSearchTotal = { [weak workspace] paneID, total in
            workspace?.paneSearchStates[paneID]?.total = total
        }
        ghosttyManager.onSearchSelected = { [weak workspace] paneID, selected in
            workspace?.paneSearchStates[paneID]?.selected = selected
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
    @Environment(TerminalWorkspaceStore.self) private var workspace
    @Environment(ProjectStore.self) private var projectStore
    @State private var hoveredTabID: String?

    private var projectTabs: [ProjectItem] { projectStore.orderedProjectTabs }

    var body: some View {
        HStack(spacing: 0) {
            // Project/worktree tab 列表
            ForEach(Array(projectTabs.enumerated()), id: \.element.id) { index, project in
                let isActive = projectStore.activeProjectID == project.id
                let isHovered = hoveredTabID == project.id

                // Determine if we should show a divider after this tab:
                // No divider between worktrees of the same root, divider between different roots
                let showDivider: Bool = {
                    guard index < projectTabs.count - 1 else { return false }
                    let next = projectTabs[index + 1]
                    // Same group: next is a worktree of current root, or both are worktrees of same parent
                    if next.worktreeOf == project.id { return false }
                    if project.isWorktree, next.isWorktree, project.worktreeOf == next.worktreeOf { return false }
                    return true
                }()

                Button {
                    projectStore.activateProject(id: project.id)
                } label: {
                    HStack(spacing: 3) {
                        // Worktree indicator
                        if project.isWorktree {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }

                        Text(project.isWorktree ? (project.worktreeBranch ?? project.name) : project.displayName)
                            .font(.system(size: 11, weight: isActive ? .semibold : .medium))
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
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .glassEffectWithTint(
                    isActive,
                    in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadius),
                    fallback: RoundedRectangle(cornerRadius: AppSpacing.cornerRadius)
                        .fill(
                            isActive
                                ? AppColors.activeBackground
                                : (isHovered ? AppColors.hoverBackground : Color.clear)
                        )
                )
                .onHover { hoveredTabID = $0 ? project.id : nil }

                // Group divider (between different root projects)
                if showDivider {
                    TerminalTabDivider()
                }
            }

            Spacer(minLength: 8)

            // 右侧：分屏按钮 + maximize 指示
            HStack(spacing: 4) {
                // Maximize indicator/restore button
                if workspace.maximizedPaneID != nil {
                    Button {
                        workspace.toggleMaximizeCurrentPane()
                    } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                    .help("Restore pane (⇧⌘↩)")
                }

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
        .animation(.easeInOut(duration: 0.15), value: projectStore.activeProjectID)
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

    @Environment(TerminalWorkspaceStore.self) private var workspace
    @Environment(GhosttyAppManager.self) private var ghosttyManager

    var body: some View {
        let paneIDs = tab.splitTree.allPaneIDs
        let isMultiPane = paneIDs.count > 1
        let isMaximized = workspace.maximizedPaneID != nil
            && paneIDs.contains(where: { $0 == workspace.maximizedPaneID })

        GeometryReader { geometry in
            let size = geometry.size
            let bounds = CGRect(origin: .zero, size: size)
            let frames = tab.splitTree.paneFrames(in: bounds)
            let dividers = tab.splitTree.dividerInfos(in: bounds)

            ZStack(alignment: .topLeading) {
                // All terminal panes with absolute positioning
                ForEach(paneIDs, id: \.self) { paneID in
                    let isMaximizedPane = isMaximized && paneID == workspace.maximizedPaneID
                    let isHiddenByMaximize = isMaximized && paneID != workspace.maximizedPaneID
                    // Maximized pane fills the entire bounds; others keep their normal frame
                    let frame = isMaximizedPane ? bounds : (frames[paneID] ?? .zero)

                    VStack(spacing: 0) {
                        if isMultiPane && !isMaximized {
                            PaneDragHandle(paneID: paneID)
                        }

                        TerminalSearchOverlay(paneID: paneID)

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
                    .animation(.easeInOut(duration: 0.15), value: isMaximized)
                    .contentShape(Rectangle())
                    .clipped()
                    .onDrop(of: [UTType.fileURL], isTargeted: Binding(
                        get: { false },
                        set: { targeted in
                            NSLog("openOwl: [FileDrop] onDrop isTargeted=%d pane=%@", targeted ? 1 : 0, paneID.uuidString)
                        }
                    )) { providers in
                        NSLog("openOwl: [FileDrop] onDrop FIRED providers=%d pane=%@", providers.count, paneID.uuidString)
                        return handleFileDrop(providers: providers, paneID: paneID)
                    }
                    .opacity(isHiddenByMaximize ? 0 : 1)
                    .allowsHitTesting(!isHiddenByMaximize)
                    .overlay {
                        // 非聚焦 pane 遮罩（轻柔）
                        if isMultiPane && !isMaximized, !workspace.isFocusedPane(paneID, in: tab.id) {
                            Color.black.opacity(0.06)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay {
                        if !isMaximized, workspace.dragOverPaneID == paneID, let zone = workspace.dropZone {
                            DropZoneHighlightView(zone: zone)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay {
                        // Always register drop target (not conditional on draggingPaneID).
                        // Conditional registration caused a timing race: SwiftUI re-renders
                        // asynchronously, so the overlay wasn't ready when the drag first
                        // entered the target pane — AppKit's TerminalScrollView caught it first.
                        //
                        // Safe to always register because paneDragTypeID is a private UTType
                        // that TerminalScrollView never registers for — Finder file drops
                        // (.fileURL) won't match it and will reach the AppKit layer unimpeded.
                        if !isMaximized, workspace.draggingPaneID != paneID {
                            Color.clear
                                .contentShape(Rectangle())
                                .onDrop(
                                    of: [UTType(exportedAs: paneDragTypeID)],
                                    delegate: PaneDropDelegate(
                                        targetPaneID: paneID,
                                        workspace: workspace,
                                        viewSize: frame.size
                                    )
                                )
                        }
                    }
                    .position(x: frame.midX, y: frame.midY)
                    .zIndex(isMaximizedPane ? 2 : 0)
                }

                // Dividers (hidden when maximized)
                if !isMaximized {
                    ForEach(dividers) { divider in
                        let isH = divider.axis == .horizontal
                        SplitDividerView(axis: divider.axis, hitAreaThickness: 6)
                            .frame(
                                width: isH ? 6 : divider.frame.width,
                                height: isH ? divider.frame.height : 6
                            )
                            .position(x: divider.frame.midX, y: divider.frame.midY)
                            .zIndex(1)
                            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("splitContainer"))
                                .onChanged { value in
                                    let pos = isH ? value.location.x : value.location.y
                                    let origin = isH ? divider.splitRect.minX : divider.splitRect.minY
                                    let splitSize = isH ? divider.splitRect.width : divider.splitRect.height
                                    guard splitSize > 1 else { return }
                                    workspace.updateSplitRatio(
                                        firstPaneID: divider.firstPaneID,
                                        secondPaneID: divider.secondPaneID,
                                        newRatio: (pos - origin) / splitSize
                                    )
                                }
                            )
                            .onTapGesture(count: 2) {
                                workspace.equalizeSplits()
                            }
                    }
                }
            }
            .coordinateSpace(name: "splitContainer")
        }
    }

    /// Handle file drops from Finder/other apps onto a terminal pane.
    /// SwiftUI-level drop bypasses NSView hierarchy issues with nested NSViewRepresentable.
    private func handleFileDrop(providers: [NSItemProvider], paneID: UUID) -> Bool {
        guard !providers.isEmpty else { return false }

        var pending = providers.count
        var paths: [String] = []
        let lock = NSLock()

        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                defer {
                    lock.lock()
                    pending -= 1
                    let done = pending == 0
                    let finalPaths = paths
                    lock.unlock()

                    if done, !finalPaths.isEmpty {
                        let payload = finalPaths
                            .map { TerminalNSView.shellEscapedPath($0) }
                            .joined(separator: " ") + " "
                        DispatchQueue.main.async {
                            self.ghosttyManager.terminalView(for: paneID)?.sendText(payload)
                        }
                    }
                }

                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                lock.lock()
                paths.append(url.standardizedFileURL.path)
                lock.unlock()
            }
        }
        return true
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
    @Environment(TerminalWorkspaceStore.self) private var workspace

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
                NSLog("openOwl: [PaneDrag] drag started pane=%@", paneID.uuidString)
                // Use private UTType — prevents TerminalScrollView (.string acceptor)
                // from intercepting this drag through the AppKit layer.
                let provider = NSItemProvider()
                let data = paneID.uuidString.data(using: .utf8)!
                provider.registerDataRepresentation(
                    forTypeIdentifier: paneDragTypeID,
                    visibility: .all
                ) { completion in completion(data, nil); return nil }
                return provider
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
        NSLog("openOwl: [PaneDropDelegate] dropEntered target=%@ draggingPane=%@",
              targetPaneID.uuidString, workspace.draggingPaneID?.uuidString ?? "nil")
        workspace.dragOverPaneID = targetPaneID
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard workspace.draggingPaneID != nil,
              workspace.draggingPaneID != targetPaneID else {
            // No active pane drag or drag is over its own source — reject silently.
            // (overlay is always-present; this fires when cursor passes over non-drag drags)
            return DropProposal(operation: .cancel)
        }

        workspace.dragOverPaneID = targetPaneID
        let newZone = detectZone(at: info.location)
        if newZone != workspace.dropZone {
            NSLog("openOwl: [PaneDropDelegate] zone changed target=%@ zone=%@",
                  targetPaneID.uuidString, "\(newZone)")
            workspace.dropZone = newZone
        }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if workspace.dragOverPaneID == targetPaneID {
            NSLog("openOwl: [PaneDropDelegate] dropExited target=%@", targetPaneID.uuidString)
            workspace.dragOverPaneID = nil
            workspace.dropZone = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let sourceID = workspace.draggingPaneID,
              sourceID != targetPaneID else {
            NSLog("openOwl: [PaneDropDelegate] performDrop SKIPPED target=%@ draggingPane=%@",
                  targetPaneID.uuidString, workspace.draggingPaneID?.uuidString ?? "nil")
            cleanup()
            return false
        }

        let zone = workspace.dropZone ?? .center
        NSLog("openOwl: [PaneDropDelegate] performDrop source=%@ target=%@ zone=%@",
              sourceID.uuidString, targetPaneID.uuidString, "\(zone)")
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
