import AppKit
import SwiftUI

/// Right-hand inspector panel. Hosts Files / Git / Deploy as switchable tabs
/// and keeps all three views mounted to preserve their `@State` (editor tabs,
/// commit drafts, scroll positions, etc.).
///
/// Tab switching, collapse, and fullscreen affordances live on `RightDockRail`
/// (the always-visible icon strip on the far right) — this view is purely
/// content + a left-edge resize handle.
struct RightDockView: View {
    @Environment(RightDockStore.self) private var dock

    /// Provided by the host so we can clamp `setWidth(...)` to a sensible upper
    /// bound (currently 50% of the window) without RightDockStore needing to
    /// know about geometry.
    let hostWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            // Drag handle on the left edge — hidden when fullscreen (ignores
            // `width`) or when the active tab is list-only (effectiveWidth
            // overrides `width` with a fixed `listOnlyWidth` either way).
            if !dock.isFullscreen && dock.showsDetailForActiveTab {
                ResizeHandle(
                    currentWidth: dock.width,
                    onResize: { proposed in
                        dock.setWidth(proposed, maxWidth: hostWidth * 0.5)
                    }
                )
            }

            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppPalette.base)
    }

    private var contentArea: some View {
        ZStack {
            // All three views stay mounted so their @State (editor tabs, commit
            // drafts, scroll positions) survives tab switches. Visibility is
            // controlled by opacity + allowsHitTesting.
            NavigationStack {
                FileExplorerView()
            }
            .opacity(dock.activeTab == .files ? 1 : 0)
            .allowsHitTesting(dock.activeTab == .files)

            NavigationStack {
                GitChangesView()
            }
            .opacity(dock.activeTab == .git ? 1 : 0)
            .allowsHitTesting(dock.activeTab == .git)

            NavigationStack {
                DeploymentPanelView()
            }
            .opacity(dock.activeTab == .deploy ? 1 : 0)
            .allowsHitTesting(dock.activeTab == .deploy)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Resize Handle

/// 4pt-wide invisible hit zone on the left edge. Reports an absolute proposed
/// width (computed from the width-at-drag-start + cumulative translation) so
/// the gesture is immune to view rebuilds — a delta-based @GestureState
/// version produced visible jitter as the dock rebuilt on every width change.
private struct ResizeHandle: View {
    let currentWidth: CGFloat
    let onResize: (CGFloat) -> Void

    @State private var dragStartWidth: CGFloat?
    @State private var hovering = false

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 4)
            .overlay(
                Rectangle()
                    .fill(hovering ? AppPalette.accent.opacity(0.4) : Color.clear)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            )
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                if inside {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                // .global is critical: as the dock grows the handle moves
                // left with it, and a .local coordinate space would make the
                // mouse appear to teleport relative to the handle each frame,
                // producing a feedback-loop jitter. Global coords are stable
                // because they don't depend on view position.
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if dragStartWidth == nil {
                            dragStartWidth = currentWidth
                        }
                        // Handle is on the LEFT edge: dragging left makes the
                        // panel wider, so subtract the (negative) translation.
                        let proposed = (dragStartWidth ?? currentWidth) - value.translation.width
                        onResize(proposed)
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                    }
            )
    }
}
