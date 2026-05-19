import SwiftUI

/// Tab bar shown above the standalone terminal — mirrors ghostty's
/// multi-tab UX for the free-terminal namespace. Project terminals don't
/// use this bar (they use sidebar worktrees and split panes for layout).
struct FreeTerminalTabBar: View {
    @Environment(TerminalWorkspaceStore.self) private var workspace

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(workspace.visibleTabs) { tab in
                    FreeTerminalTabButton(
                        tab: tab,
                        isActive: workspace.activeTabID == tab.id,
                        canClose: workspace.visibleTabs.count > 1
                    )
                }

                // Inline `+` button at the end of the tab list — always
                // visible because it scrolls with the tabs. (Earlier
                // attempt put it outside the ScrollView in a flanking
                // HStack, but ScrollView's greedy horizontal sizing
                // squeezed the button out of the visible area.)
                Button {
                    _ = workspace.newTab()
                    // newTab itself doesn't fire the host sync callback
                    // (it's also called from store-internal paths where
                    // re-entering sync would recurse), so signal explicitly.
                    workspace.notifyContextChange()
                } label: {
                    Image(systemName: "plus")
                        .font(AppFonts.toolbarIcon)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New tab (⌘T)")
                .accessibilityLabel("New tab (⌘T)")
                .padding(.leading, 4)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .frame(height: AppSpacing.headerHeight)
        .background(AppPalette.elevated)
    }
}

private struct FreeTerminalTabButton: View {
    let tab: TerminalTabState
    let isActive: Bool
    let canClose: Bool

    @Environment(TerminalWorkspaceStore.self) private var workspace
    @State private var hovering = false

    private var displayTitle: String {
        // Prefer the focused pane's OSC-reported title, then any pane in the
        // tab, else fall back to the tab's stored title ("Tab 1", etc.).
        if let pid = tab.focusedPaneID ?? tab.splitTree.firstPaneID,
           let title = workspace.paneTitles[pid], !title.isEmpty {
            return title
        }
        return tab.title
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(displayTitle)
                .font(AppFonts.body)
                .foregroundStyle(isActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .lineLimit(1)

            if canClose && (hovering || isActive) {
                Button {
                    workspace.closeTab(id: tab.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(AppFonts.smallIcon)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close tab")
                .accessibilityLabel("Close tab")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusSmall, style: .continuous)
                .fill(isActive ? AppColors.activeBackground : (hovering ? AppColors.hoverBackground : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            workspace.selectTab(id: tab.id)
        }
        .onHover { hovering = $0 }
    }
}
