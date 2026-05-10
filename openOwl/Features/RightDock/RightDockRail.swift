import SwiftUI

/// Always-visible vertical icon strip on the far right of the detail area.
///
/// Acts as both the entry point (tap an icon to open the dock) and the tab
/// switcher (tap another icon to switch tabs, tap the active icon to collapse).
/// A bottom fullscreen toggle replaces the old in-panel header button so the
/// affordance never gets clipped on narrow windows.
struct RightDockRail: View {
    @Environment(RightDockStore.self) private var dock

    static let width: CGFloat = 28

    var body: some View {
        VStack(spacing: 4) {
            ForEach(RightDockTab.allCases) { tab in
                RailButton(
                    systemImage: tab.systemImage,
                    isActive: dock.isExpanded && dock.activeTab == tab,
                    help: tab.title,
                    action: { dock.toggle(tab: tab) }
                )
            }

            Spacer(minLength: 0)

            // Always-visible separator + fullscreen button. Earlier we hid
            // the fullscreen affordance when the panel was collapsed, but
            // users couldn't find it without first opening a tab — making it
            // permanent (and auto-expanding on tap when collapsed) keeps the
            // entry point stable.
            Rectangle()
                .fill(AppPalette.border)
                .frame(width: 16, height: 1)
                .padding(.vertical, 2)

            RailButton(
                systemImage: dock.isFullscreen
                    ? "arrow.down.right.and.arrow.up.left.square.fill"
                    : "arrow.up.left.and.arrow.down.right.square",
                isActive: dock.isFullscreen,
                help: dock.isFullscreen ? "Exit fullscreen" : "Fullscreen panel",
                font: AppFonts.body,
                action: {
                    if !dock.isExpanded {
                        dock.expand(tab: dock.activeTab)
                    }
                    dock.toggleFullscreen()
                }
            )
        }
        .padding(.vertical, 6)
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .background(AppPalette.elevated)
    }
}

// MARK: - Rail Button

private struct RailButton: View {
    let systemImage: String
    let isActive: Bool
    let help: String
    var font: Font = AppFonts.toolbarIcon
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .leading) {
                // Active indicator: 2pt accent bar on the left edge.
                Rectangle()
                    .fill(isActive ? AppPalette.accent : Color.clear)
                    .frame(width: 2)

                Image(systemName: systemImage)
                    .font(font)
                    .foregroundStyle(
                        isActive
                            ? AnyShapeStyle(AppPalette.accent)
                            : AnyShapeStyle(.secondary)
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(width: RightDockRail.width, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(rowBackground)
                    .padding(.horizontal, 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }

    private var rowBackground: Color {
        if isActive { return AppPalette.accent.opacity(0.18) }
        if hovering { return AppColors.hoverBackground }
        return .clear
    }
}
