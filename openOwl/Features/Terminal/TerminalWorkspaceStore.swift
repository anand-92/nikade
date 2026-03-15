import CoreGraphics
import Foundation
import Combine

struct TerminalTabState: Identifiable, Equatable {
    let id: UUID
    var title: String
    var splitTree: TerminalSplitNode
    var focusedPaneID: UUID?
}

enum TerminalSplitAxis: String, Equatable {
    /// Left-right layout
    case horizontal
    /// Top-bottom layout
    case vertical
}

enum TerminalFocusDirection {
    case left
    case right
    case up
    case down
}

struct SplitDividerInfo: Identifiable {
    /// Stable ID derived from the two pane IDs this divider separates
    var id: String { "\(firstPaneID)-\(secondPaneID)" }
    let axis: TerminalSplitAxis
    let ratio: Double
    let frame: CGRect
    let firstPaneID: UUID
    let secondPaneID: UUID
}

enum PaneDropZone: Equatable {
    case left, right, top, bottom, center
}

enum TerminalCloseAction {
    case none
    case closeWindow
}

indirect enum TerminalSplitNode: Equatable {
    case leaf(UUID)
    case split(
        axis: TerminalSplitAxis,
        ratio: Double,
        first: TerminalSplitNode,
        second: TerminalSplitNode
    )

    var leafCount: Int {
        switch self {
        case .leaf:
            return 1
        case .split(_, _, let first, let second):
            return first.leafCount + second.leafCount
        }
    }

    var firstPaneID: UUID? {
        switch self {
        case .leaf(let paneID):
            return paneID
        case .split(_, _, let first, _):
            return first.firstPaneID
        }
    }

    func containsPane(_ paneID: UUID) -> Bool {
        switch self {
        case .leaf(let id):
            return id == paneID
        case .split(_, _, let first, let second):
            return first.containsPane(paneID) || second.containsPane(paneID)
        }
    }

    /// Update the ratio of the nearest split ancestor containing `targetPaneID` in its first child.
    func updatingRatio(forPaneID targetPaneID: UUID, newRatio: Double) -> TerminalSplitNode {
        switch self {
        case .leaf:
            return self
        case .split(let axis, let ratio, let first, let second):
            // If the first child contains the target pane, this is the split to update
            if first.containsPane(targetPaneID) && !second.containsPane(targetPaneID) {
                // But first, recurse into the first child to see if there's a deeper match
                let updatedFirst = first.updatingRatio(forPaneID: targetPaneID, newRatio: newRatio)
                if updatedFirst != first {
                    return .split(axis: axis, ratio: ratio, first: updatedFirst, second: second)
                }
                // This is the closest split — update ratio
                let clamped = min(max(newRatio, 0.1), 0.9)
                return .split(axis: axis, ratio: clamped, first: first, second: second)
            }
            // If the second child contains it, check if there's a deeper split to update
            if second.containsPane(targetPaneID) {
                let updatedSecond = second.updatingRatio(forPaneID: targetPaneID, newRatio: newRatio)
                return .split(axis: axis, ratio: ratio, first: first, second: updatedSecond)
            }
            return self
        }
    }

    /// Update the ratio of the split node that directly contains `firstPaneID` in its first subtree.
    /// This variant is used by the divider drag, where we know which split to target.
    func updatingSplitRatio(whereFirstContains firstPaneID: UUID, andSecondContains secondPaneID: UUID, newRatio: Double) -> TerminalSplitNode {
        switch self {
        case .leaf:
            return self
        case .split(let axis, let ratio, let first, let second):
            if first.containsPane(firstPaneID) && second.containsPane(secondPaneID) {
                // Check if a deeper split matches
                let updatedFirst = first.updatingSplitRatio(whereFirstContains: firstPaneID, andSecondContains: secondPaneID, newRatio: newRatio)
                if updatedFirst != first {
                    return .split(axis: axis, ratio: ratio, first: updatedFirst, second: second)
                }
                let updatedSecond = second.updatingSplitRatio(whereFirstContains: firstPaneID, andSecondContains: secondPaneID, newRatio: newRatio)
                if updatedSecond != second {
                    return .split(axis: axis, ratio: ratio, first: first, second: updatedSecond)
                }
                // This is the target split
                let clamped = min(max(newRatio, 0.1), 0.9)
                return .split(axis: axis, ratio: clamped, first: first, second: second)
            }
            // Recurse
            let updatedFirst = first.updatingSplitRatio(whereFirstContains: firstPaneID, andSecondContains: secondPaneID, newRatio: newRatio)
            let updatedSecond = second.updatingSplitRatio(whereFirstContains: firstPaneID, andSecondContains: secondPaneID, newRatio: newRatio)
            if updatedFirst != first || updatedSecond != second {
                return .split(axis: axis, ratio: ratio, first: updatedFirst, second: updatedSecond)
            }
            return self
        }
    }

    /// Swap two leaf panes in the tree.
    func swappingPanes(_ a: UUID, _ b: UUID) -> TerminalSplitNode {
        switch self {
        case .leaf(let id):
            if id == a { return .leaf(b) }
            if id == b { return .leaf(a) }
            return self
        case .split(let axis, let ratio, let first, let second):
            return .split(
                axis: axis,
                ratio: ratio,
                first: first.swappingPanes(a, b),
                second: second.swappingPanes(a, b)
            )
        }
    }

    /// Reset all ratios to 0.5 recursively.
    func equalized() -> TerminalSplitNode {
        switch self {
        case .leaf:
            return self
        case .split(let axis, _, let first, let second):
            return .split(axis: axis, ratio: 0.5, first: first.equalized(), second: second.equalized())
        }
    }

    /// Insert newPaneID beside targetPaneID. If `newPaneFirst`, the new pane is the first child.
    func insertingPaneBeside(_ targetPaneID: UUID, newPaneID: UUID, axis: TerminalSplitAxis, newPaneFirst: Bool) -> TerminalSplitNode? {
        switch self {
        case .leaf(let id):
            guard id == targetPaneID else { return nil }
            let first: TerminalSplitNode = newPaneFirst ? .leaf(newPaneID) : .leaf(id)
            let second: TerminalSplitNode = newPaneFirst ? .leaf(id) : .leaf(newPaneID)
            return .split(axis: axis, ratio: 0.5, first: first, second: second)

        case .split(let currentAxis, let ratio, let first, let second):
            if let updatedFirst = first.insertingPaneBeside(targetPaneID, newPaneID: newPaneID, axis: axis, newPaneFirst: newPaneFirst) {
                return .split(axis: currentAxis, ratio: ratio, first: updatedFirst, second: second)
            }
            if let updatedSecond = second.insertingPaneBeside(targetPaneID, newPaneID: newPaneID, axis: axis, newPaneFirst: newPaneFirst) {
                return .split(axis: currentAxis, ratio: ratio, first: first, second: updatedSecond)
            }
            return nil
        }
    }

    func insertingSplit(at paneID: UUID, newPaneID: UUID, axis: TerminalSplitAxis) -> TerminalSplitNode? {
        switch self {
        case .leaf(let id):
            guard id == paneID else { return nil }
            return .split(
                axis: axis,
                ratio: 0.5,
                first: .leaf(id),
                second: .leaf(newPaneID)
            )

        case .split(let currentAxis, let ratio, let first, let second):
            if let updatedFirst = first.insertingSplit(at: paneID, newPaneID: newPaneID, axis: axis) {
                return .split(axis: currentAxis, ratio: ratio, first: updatedFirst, second: second)
            }
            if let updatedSecond = second.insertingSplit(at: paneID, newPaneID: newPaneID, axis: axis) {
                return .split(axis: currentAxis, ratio: ratio, first: first, second: updatedSecond)
            }
            return nil
        }
    }

    func removingPane(_ paneID: UUID) -> TerminalSplitNode? {
        switch self {
        case .leaf(let id):
            return id == paneID ? nil : self

        case .split(let axis, let ratio, let first, let second):
            let updatedFirst = first.removingPane(paneID)
            let updatedSecond = second.removingPane(paneID)

            if let updatedFirst, let updatedSecond {
                return .split(axis: axis, ratio: ratio, first: updatedFirst, second: updatedSecond)
            }
            if let updatedFirst {
                return updatedFirst
            }
            if let updatedSecond {
                return updatedSecond
            }
            return nil
        }
    }

    /// All leaf pane IDs in tree order.
    var allPaneIDs: [UUID] {
        switch self {
        case .leaf(let id): return [id]
        case .split(_, _, let first, let second):
            return first.allPaneIDs + second.allPaneIDs
        }
    }

    func normalizedPaneFrames() -> [UUID: CGRect] {
        paneFrames(in: CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// Calculate pane frames in actual pixel coordinates.
    func paneFrames(in rect: CGRect) -> [UUID: CGRect] {
        switch self {
        case .leaf(let paneID):
            return [paneID: rect]

        case .split(let axis, let ratio, let first, let second):
            let (firstRect, secondRect) = splitRects(rect: rect, axis: axis, ratio: ratio)
            var output = first.paneFrames(in: firstRect)
            output.merge(second.paneFrames(in: secondRect)) { _, new in new }
            return output
        }
    }

    /// Info about each divider in the tree for flat rendering.
    func dividerInfos(in rect: CGRect) -> [SplitDividerInfo] {
        switch self {
        case .leaf:
            return []
        case .split(let axis, let ratio, let first, let second):
            let (firstRect, secondRect) = splitRects(rect: rect, axis: axis, ratio: ratio)
            let clampedRatio = min(max(ratio, 0.1), 0.9)

            let dividerFrame: CGRect
            switch axis {
            case .horizontal:
                let x = rect.minX + rect.width * clampedRatio
                dividerFrame = CGRect(x: x - 0.5, y: rect.minY, width: 1, height: rect.height)
            case .vertical:
                let y = rect.minY + rect.height * clampedRatio
                dividerFrame = CGRect(x: rect.minX, y: y - 0.5, width: rect.width, height: 1)
            }

            let info = SplitDividerInfo(
                axis: axis,
                ratio: clampedRatio,
                frame: dividerFrame,
                firstPaneID: first.firstPaneID ?? UUID(),
                secondPaneID: second.firstPaneID ?? UUID()
            )

            return [info] + first.dividerInfos(in: firstRect) + second.dividerInfos(in: secondRect)
        }
    }

    private func splitRects(rect: CGRect, axis: TerminalSplitAxis, ratio: Double) -> (CGRect, CGRect) {
        let clampedRatio = min(max(ratio, 0.1), 0.9)
        switch axis {
        case .horizontal:
            let w = rect.width * clampedRatio
            return (
                CGRect(x: rect.minX, y: rect.minY, width: w, height: rect.height),
                CGRect(x: rect.minX + w, y: rect.minY, width: rect.width - w, height: rect.height)
            )
        case .vertical:
            let h = rect.height * clampedRatio
            return (
                CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: h),
                CGRect(x: rect.minX, y: rect.minY + h, width: rect.width, height: rect.height - h)
            )
        }
    }
}

@MainActor
final class TerminalWorkspaceStore: ObservableObject {
    @Published private(set) var tabs: [TerminalTabState] = []
    @Published var activeTabID: UUID?

    /// Set by the host app to request first responder hand-off to a pane's NSView.
    var focusPaneHandler: ((UUID) -> Void)?

    /// Drag-to-reposition state
    @Published var draggingPaneID: UUID?
    @Published var dragOverPaneID: UUID?
    @Published var dropZone: PaneDropZone?

    private var nextTabNumber = 1

    // Per-project terminal tracking
    @Published private(set) var activeProjectID: String?
    private var tabProjectMap: [UUID: String] = [:]  // tabID → projectID

    func switchProject(_ projectID: String?) {
        activeProjectID = projectID

        // Create initial tab if project has none
        let projectTabs = tabs.filter { tabProjectMap[$0.id] == projectID }
        if projectTabs.isEmpty, let projectID {
            _ = newTab(forProject: projectID)
        } else if let firstTab = projectTabs.first {
            activeTabID = firstTab.id
        }
    }

    /// Tabs for the currently active project
    var visibleTabs: [TerminalTabState] {
        guard let activeProjectID else { return tabs }
        return tabs.filter { tabProjectMap[$0.id] == activeProjectID }
    }

    /// Check if a tab belongs to the active project
    func isTabVisible(_ tabID: UUID) -> Bool {
        guard let activeProjectID else { return true }
        return tabProjectMap[tabID] == activeProjectID
    }

    func ensureInitialTab() {
        guard tabs.isEmpty else { return }
        _ = newTab()
    }

    @discardableResult
    func newTab(makeActive: Bool = true, forProject projectID: String? = nil) -> UUID {
        let paneID = UUID()
        let tabID = UUID()

        let tab = TerminalTabState(
            id: tabID,
            title: "Tab \(nextTabNumber)",
            splitTree: .leaf(paneID),
            focusedPaneID: paneID
        )
        nextTabNumber += 1

        tabs.append(tab)
        tabProjectMap[tabID] = projectID ?? activeProjectID

        if makeActive {
            activeTabID = tabID
            requestFocus(for: paneID)
        }

        return tabID
    }

    func selectTab(index: Int) {
        guard tabs.indices.contains(index) else { return }
        activeTabID = tabs[index].id

        if tabs[index].focusedPaneID == nil {
            tabs[index].focusedPaneID = tabs[index].splitTree.firstPaneID
        }

        if let paneID = tabs[index].focusedPaneID {
            requestFocus(for: paneID)
        }
    }

    func splitCurrent(axis: TerminalSplitAxis) {
        guard let index = activeTabIndex else { return }
        var tab = tabs[index]

        guard let currentPane = tab.focusedPaneID ?? tab.splitTree.firstPaneID else { return }
        let newPane = UUID()

        guard let newTree = tab.splitTree.insertingSplit(at: currentPane, newPaneID: newPane, axis: axis) else { return }

        tab.splitTree = newTree
        tab.focusedPaneID = newPane
        tabs[index] = tab

        requestFocus(for: newPane)
    }

    func closeCurrent() -> TerminalCloseAction {
        guard let index = activeTabIndex else { return .closeWindow }
        var tab = tabs[index]

        if tab.splitTree.leafCount > 1 {
            closeFocusedPane(in: &tab)
            tabs[index] = tab
            return .none
        }

        if tabs.count > 1 {
            let removedID = tabs[index].id
            tabProjectMap.removeValue(forKey: removedID)
            tabs.remove(at: index)

            // Switch to next visible tab for this project
            let visible = visibleTabs
            let fallback = visible.first ?? tabs.last
            activeTabID = fallback?.id

            if let fbID = activeTabID, let fbIdx = tabs.firstIndex(where: { $0.id == fbID }) {
                if tabs[fbIdx].focusedPaneID == nil {
                    tabs[fbIdx].focusedPaneID = tabs[fbIdx].splitTree.firstPaneID
                }
                if let paneID = tabs[fbIdx].focusedPaneID {
                    requestFocus(for: paneID)
                }
            }
            return .none
        }

        return .closeWindow
    }

    func focusNeighbor(_ direction: TerminalFocusDirection) {
        guard let index = activeTabIndex else { return }
        var tab = tabs[index]

        guard let currentPane = tab.focusedPaneID ?? tab.splitTree.firstPaneID else { return }
        let frames = tab.splitTree.normalizedPaneFrames()
        guard let currentFrame = frames[currentPane] else { return }

        let candidate = nextPaneID(from: currentFrame, currentPaneID: currentPane, frames: frames, direction: direction)
        guard let candidate else { return }

        tab.focusedPaneID = candidate
        tabs[index] = tab
        requestFocus(for: candidate)
    }

    func updateSplitRatio(firstPaneID: UUID, secondPaneID: UUID, newRatio: Double) {
        guard let index = activeTabIndex else { return }
        var tab = tabs[index]
        let newTree = tab.splitTree.updatingSplitRatio(
            whereFirstContains: firstPaneID,
            andSecondContains: secondPaneID,
            newRatio: newRatio
        )
        tab.splitTree = newTree
        tabs[index] = tab
    }

    func swapPaneWithNeighbor(_ direction: TerminalFocusDirection) {
        guard let index = activeTabIndex else { return }
        var tab = tabs[index]
        guard let currentPane = tab.focusedPaneID ?? tab.splitTree.firstPaneID else { return }
        let frames = tab.splitTree.normalizedPaneFrames()
        guard let currentFrame = frames[currentPane] else { return }

        guard let neighborID = nextPaneID(from: currentFrame, currentPaneID: currentPane, frames: frames, direction: direction) else { return }

        tab.splitTree = tab.splitTree.swappingPanes(currentPane, neighborID)
        // Focus follows the original pane
        tab.focusedPaneID = currentPane
        tabs[index] = tab
        requestFocus(for: currentPane)
    }

    func movePaneToTarget(sourceID: UUID, targetID: UUID, zone: PaneDropZone) {
        guard sourceID != targetID else { return }
        guard let index = activeTabIndex else { return }
        var tab = tabs[index]

        if zone == .center {
            // Swap: tree shape stays the same, just swap leaf IDs
            tab.splitTree = tab.splitTree.swappingPanes(sourceID, targetID)
        } else {
            // Edge drop: use a placeholder to avoid removing sourceID from the tree,
            // which would destroy the terminal surface.
            let placeholderID = UUID()
            let axis: TerminalSplitAxis
            let sourceFirst: Bool

            switch zone {
            case .left:   axis = .horizontal; sourceFirst = true
            case .right:  axis = .horizontal; sourceFirst = false
            case .top:    axis = .vertical;   sourceFirst = true
            case .bottom: axis = .vertical;   sourceFirst = false
            case .center: return
            }

            // Step 1: Replace source with placeholder (keeps tree structure valid)
            var tree = tab.splitTree.swappingPanes(sourceID, placeholderID)
            // Step 2: Insert sourceID beside targetID
            guard let withSplit = tree.insertingPaneBeside(targetID, newPaneID: sourceID, axis: axis, newPaneFirst: sourceFirst) else { return }
            tree = withSplit
            // Step 3: Remove the placeholder
            guard let final = tree.removingPane(placeholderID) else { return }
            tab.splitTree = final
        }

        tab.focusedPaneID = sourceID
        tabs[index] = tab
        requestFocus(for: sourceID)
    }

    func swapPanes(_ a: UUID, _ b: UUID) {
        guard a != b else { return }
        guard let index = activeTabIndex else { return }
        var tab = tabs[index]
        tab.splitTree = tab.splitTree.swappingPanes(a, b)
        tabs[index] = tab
    }

    func equalizeSplits() {
        guard let index = activeTabIndex else { return }
        var tab = tabs[index]
        tab.splitTree = tab.splitTree.equalized()
        tabs[index] = tab
    }

    func updateTitle(for paneID: UUID, title: String) {
        let normalized = normalizeTabTitle(title)
        guard !normalized.isEmpty else { return }

        for index in tabs.indices {
            guard tabs[index].splitTree.containsPane(paneID) else { continue }
            tabs[index].title = normalized
            return
        }
    }

    /// Called from TerminalNSView focus changes.
    func focusPane(_ paneID: UUID) {
        for index in tabs.indices {
            guard tabs[index].splitTree.containsPane(paneID) else { continue }
            let targetTabID = tabs[index].id
            if activeTabID == targetTabID && tabs[index].focusedPaneID == paneID {
                return
            }

            activeTabID = targetTabID
            tabs[index].focusedPaneID = paneID

            return
        }
    }

    func isPaneVisible(_ paneID: UUID, in tabID: UUID) -> Bool {
        guard activeTabID == tabID else { return false }
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return false }
        return tab.splitTree.containsPane(paneID)
    }

    func isFocusedPane(_ paneID: UUID, in tabID: UUID) -> Bool {
        guard activeTabID == tabID else { return false }
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return false }
        return tab.focusedPaneID == paneID
    }

    private var activeTabIndex: Int? {
        guard let activeTabID else { return nil }
        return tabs.firstIndex(where: { $0.id == activeTabID })
    }

    private func closeFocusedPane(in tab: inout TerminalTabState) {
        guard let currentPane = tab.focusedPaneID ?? tab.splitTree.firstPaneID else { return }

        let oldFrames = tab.splitTree.normalizedPaneFrames()
        guard let oldFrame = oldFrames[currentPane] else { return }
        guard let newTree = tab.splitTree.removingPane(currentPane) else { return }

        tab.splitTree = newTree

        let newFrames = newTree.normalizedPaneFrames()
        tab.focusedPaneID = nearestPaneID(to: oldFrame, in: newFrames) ?? newTree.firstPaneID

        if let nextPane = tab.focusedPaneID {
            requestFocus(for: nextPane)
        }
    }

    private func requestFocus(for paneID: UUID) {
        focusPaneHandler?(paneID)
    }

    private func normalizeTabTitle(_ rawTitle: String) -> String {
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return String(trimmed.prefix(120))
    }

    private func nextPaneID(
        from currentFrame: CGRect,
        currentPaneID: UUID,
        frames: [UUID: CGRect],
        direction: TerminalFocusDirection
    ) -> UUID? {
        let epsilon = 0.0001
        let currentCenter = CGPoint(x: currentFrame.midX, y: currentFrame.midY)

        let candidates: [(paneID: UUID, distance: CGFloat, overlap: CGFloat, crossDelta: CGFloat)] = frames.compactMap { paneID, frame in
            guard paneID != currentPaneID else { return nil }

            let isDirectionalMatch: Bool
            let distance: CGFloat
            let overlap: CGFloat
            let crossDelta: CGFloat

            switch direction {
            case .left:
                isDirectionalMatch = frame.maxX <= currentFrame.minX + epsilon
                distance = currentFrame.minX - frame.maxX
                overlap = currentFrame.intersection(frame).height
                crossDelta = abs(currentCenter.y - frame.midY)

            case .right:
                isDirectionalMatch = frame.minX >= currentFrame.maxX - epsilon
                distance = frame.minX - currentFrame.maxX
                overlap = currentFrame.intersection(frame).height
                crossDelta = abs(currentCenter.y - frame.midY)

            case .up:
                isDirectionalMatch = frame.maxY <= currentFrame.minY + epsilon
                distance = currentFrame.minY - frame.maxY
                overlap = currentFrame.intersection(frame).width
                crossDelta = abs(currentCenter.x - frame.midX)

            case .down:
                isDirectionalMatch = frame.minY >= currentFrame.maxY - epsilon
                distance = frame.minY - currentFrame.maxY
                overlap = currentFrame.intersection(frame).width
                crossDelta = abs(currentCenter.x - frame.midX)
            }

            guard isDirectionalMatch else { return nil }
            return (paneID, max(distance, 0), max(overlap, 0), crossDelta)
        }

        guard !candidates.isEmpty else { return nil }

        let sorted = candidates.sorted { lhs, rhs in
            if lhs.distance != rhs.distance {
                return lhs.distance < rhs.distance
            }
            if lhs.overlap != rhs.overlap {
                return lhs.overlap > rhs.overlap
            }
            return lhs.crossDelta < rhs.crossDelta
        }

        return sorted.first?.paneID
    }

    private func nearestPaneID(to previousFrame: CGRect, in frames: [UUID: CGRect]) -> UUID? {
        let previousCenter = CGPoint(x: previousFrame.midX, y: previousFrame.midY)

        return frames.min { lhs, rhs in
            let leftDistance = hypot(lhs.value.midX - previousCenter.x, lhs.value.midY - previousCenter.y)
            let rightDistance = hypot(rhs.value.midX - previousCenter.x, rhs.value.midY - previousCenter.y)
            return leftDistance < rightDistance
        }?.key
    }
}
