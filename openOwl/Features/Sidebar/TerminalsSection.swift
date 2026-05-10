import SwiftUI

/// Single-row "Terminal" entry at the top of the sidebar — replaces the
/// collapsible multi-row TERMINALS group. There's only ever one
/// standalone-terminal namespace; multiple sessions live as tabs inside
/// that namespace's `FreeTerminalTabBar` above the terminal content (which
/// mirrors ghostty's native tab-based UX).
struct TerminalEntryRow: View {
    @Environment(ProjectStore.self) private var projectStore
    @Environment(TerminalWorkspaceStore.self) private var workspace

    /// Tag value used for List selection — this is the id of the (single)
    /// free terminal item in `ProjectStore.freeTerminals`. The store
    /// guarantees at least one free terminal exists, so the optional
    /// unwrap is just an exhaustive guard.
    static func rowTag(for terminalID: UUID) -> String {
        "free-\(terminalID.uuidString)"
    }

    static func terminalID(fromTag tag: String) -> UUID? {
        guard tag.hasPrefix("free-") else { return nil }
        return UUID(uuidString: String(tag.dropFirst("free-".count)))
    }

    private var unreadCount: Int {
        guard let id = projectStore.freeTerminals.first?.id else { return 0 }
        return workspace.bellCount(for: .freeTerminal(id))
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "terminal")
                .font(AppFonts.body)

            Text("Terminal")
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
        }
    }
}
