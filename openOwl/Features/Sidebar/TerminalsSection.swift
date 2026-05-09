import SwiftUI

/// "TERMINALS" sidebar section: lists free (project-independent) terminals.
///
/// Each row mirrors the look of BranchRow/WorktreeRow — the title follows the
/// shell-reported pane title (OSC 0/2), so once `zsh` updates its terminal
/// title the row updates too.
struct TerminalsSection: View {
    @Environment(ProjectStore.self) private var projectStore
    @Environment(TerminalWorkspaceStore.self) private var workspace
    @Binding var isExpanded: Bool

    var body: some View {
        // Header
        TerminalsHeaderRow(isExpanded: $isExpanded)

        if isExpanded {
            ForEach(projectStore.freeTerminals) { terminal in
                FreeTerminalRow(
                    terminal: terminal,
                    canClose: projectStore.freeTerminals.count > 1
                )
                .tag(rowTag(for: terminal.id))
            }
        }
    }

    /// Tag value used for List selection. Free-terminal tags use a "free-" prefix
    /// so SidebarView's selection binding can route them.
    static func rowTag(for terminalID: UUID) -> String {
        "free-\(terminalID.uuidString)"
    }

    /// Inverse of rowTag — extracts a terminal id from a tag, or nil if the tag
    /// is not a free-terminal tag.
    static func terminalID(fromTag tag: String) -> UUID? {
        guard tag.hasPrefix("free-") else { return nil }
        let raw = String(tag.dropFirst("free-".count))
        return UUID(uuidString: raw)
    }

    private func rowTag(for terminalID: UUID) -> String {
        Self.rowTag(for: terminalID)
    }
}

// MARK: - Header

private struct TerminalsHeaderRow: View {
    @Environment(ProjectStore.self) private var projectStore
    @Binding var isExpanded: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(AppFonts.badge.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 12, height: 12)

                Text("TERMINALS")
                    .font(AppFonts.sectionHeader)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            }

            Spacer(minLength: 0)

            if hovering {
                Button {
                    let added = projectStore.addFreeTerminal()
                    projectStore.activate(.freeTerminal(added.id))
                } label: {
                    Image(systemName: "plus")
                        .font(AppFonts.toolbarIcon)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("New terminal")
                .accessibilityLabel("New terminal")
            }
        }
        .onHover { hovering = $0 }
    }
}

// MARK: - Free Terminal Row

private struct FreeTerminalRow: View {
    let terminal: FreeTerminalItem
    let canClose: Bool

    @Environment(ProjectStore.self) private var projectStore
    @Environment(TerminalWorkspaceStore.self) private var workspace
    @State private var hovering = false

    private var paneInfos: [PaneInfo] {
        workspace.paneInfos(for: .freeTerminal(terminal.id))
    }

    private var unreadCount: Int {
        workspace.bellCount(for: .freeTerminal(terminal.id))
    }

    private var displayTitle: String {
        // Follow ghostty quick terminal style: use the most recent pane's title,
        // falling back to "Terminal" before the shell has set one.
        if let first = paneInfos.first, !first.title.isEmpty {
            return first.title
        }
        return "Terminal"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "terminal")
                    .font(AppFonts.body)

                Text(displayTitle)
                    .font(AppFonts.body)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if unreadCount > 0 {
                    Text("\(unreadCount)")
                        .font(AppFonts.badge)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .background(Capsule().fill(Color.accentColor))
                }

                if hovering, canClose {
                    Button {
                        projectStore.removeFreeTerminal(id: terminal.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(AppFonts.smallIcon)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .help("Close terminal")
                    .accessibilityLabel("Close terminal")
                }
            }
            .padding(.leading, 16)

            if !paneInfos.isEmpty {
                ForEach(paneInfos) { info in
                    FreeTerminalPaneStatusRow(info: info)
                }
            }
        }
        .onHover { hovering = $0 }
    }
}

// MARK: - Pane Status Row (mirrors SidebarView's PaneStatusRow)

private struct FreeTerminalPaneStatusRow: View {
    let info: PaneInfo

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(info.hasBell ? Color.accentColor : Color.secondary.opacity(0.4))
                .frame(width: 7, height: 7)

            Text(info.title)
                .font(AppFonts.secondaryLabel)
                .foregroundStyle(info.hasBell ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .lineLimit(1)

            Spacer(minLength: 4)

            if info.hasBell {
                Image(systemName: "bell.fill")
                    .font(AppFonts.smallIcon)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.leading, 24)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
    }
}
