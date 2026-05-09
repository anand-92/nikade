import AppKit
import SwiftUI

/// Right-hand inspector panel. Hosts Files / Git / Deploy as switchable tabs,
/// keeps all three views mounted to preserve their `@State` (editor tabs,
/// commit drafts, scroll positions, etc.), and supports collapse + fullscreen.
///
/// The hosting layout (ContentView) is responsible for sizing — this view fills
/// the space it's given. Width persistence and the drag-to-resize handle live
/// here so the dock owns its own affordance set.
struct RightDockView: View {
    @Environment(RightDockStore.self) private var dock

    /// Provided by the host so we can clamp `setWidth(...)` to a sensible upper
    /// bound (currently 50% of the window) without RightDockStore needing to
    /// know about geometry.
    let hostWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            // Drag handle on the left edge — only shown when not fullscreen,
            // since fullscreen panel ignores `width` entirely.
            if !dock.isFullscreen {
                ResizeHandle { translationX in
                    let proposed = dock.width - translationX
                    dock.setWidth(proposed, maxWidth: hostWidth * 0.5)
                }
            }

            VStack(spacing: 0) {
                tabBar

                Divider()

                contentArea
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppPalette.base)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(RightDockTab.allCases) { tab in
                TabBarItem(tab: tab, isActive: dock.activeTab == tab) {
                    dock.activeTab = tab
                }
            }

            Spacer(minLength: 8)

            Button {
                dock.toggleFullscreen()
            } label: {
                Image(systemName: dock.isFullscreen
                      ? "arrow.down.right.and.arrow.up.left"
                      : "arrow.up.left.and.arrow.down.right")
                    .font(AppFonts.toolbarIcon)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(dock.isFullscreen ? "Exit fullscreen" : "Fullscreen")
            .accessibilityLabel(dock.isFullscreen ? "Exit fullscreen" : "Fullscreen")

            Button {
                dock.collapse()
            } label: {
                Image(systemName: "sidebar.right")
                    .font(AppFonts.toolbarIcon)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Collapse panel")
            .accessibilityLabel("Collapse panel")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - Content Area

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

// MARK: - Tab Bar Item

private struct TabBarItem: View {
    let tab: RightDockTab
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: tab.systemImage)
                    .font(AppFonts.toolbarIcon)
                Text(tab.title)
                    .font(AppFonts.body.weight(isActive ? .semibold : .regular))
            }
            .foregroundStyle(isActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? AppPalette.accent.opacity(0.18) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .help(tab.title)
    }
}

// MARK: - Resize Handle

/// 4pt-wide invisible hit zone on the left edge that drags the panel wider/narrower.
/// Drag delta is reported as raw translation; the host translates that into a width
/// proposal via `setWidth(_:maxWidth:)` so clamping lives in the store.
private struct ResizeHandle: View {
    let onDrag: (CGFloat) -> Void

    @GestureState private var translationX: CGFloat = 0
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
                DragGesture(minimumDistance: 0)
                    .updating($translationX) { value, state, _ in
                        let delta = value.translation.width - state
                        state = value.translation.width
                        onDrag(delta)
                    }
            )
    }
}
