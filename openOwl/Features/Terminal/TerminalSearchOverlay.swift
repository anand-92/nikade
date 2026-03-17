import SwiftUI

/// Floating search bar overlaid on a terminal pane.
/// Debounces short queries (< 3 chars) by 300ms, fires immediately for >= 3 chars.
struct TerminalSearchOverlay: View {
    let paneID: UUID
    @Environment(TerminalWorkspaceStore.self) private var workspace
    @Environment(GhosttyAppManager.self) private var ghosttyManager
    @FocusState private var isTextFieldFocused: Bool

    /// Task handle for debounced search
    @State private var debounceTask: Task<Void, Never>?

    private var searchState: TerminalSearchState? {
        workspace.paneSearchStates[paneID]
    }

    var body: some View {
        if let state = searchState, state.isSearching {
            searchBar(state)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func searchBar(_ state: TerminalSearchState) -> some View {
        HStack(spacing: 6) {
            // Search field
            TextField("Search...", text: Bindable(state).needle)
                .textFieldStyle(.plain)
                .font(AppFonts.body)
                .focused($isTextFieldFocused)
                .frame(minWidth: 120, maxWidth: 200)
                .onKeyPress(keys: [.return], phases: .down) { press in
                    if press.modifiers.contains(.shift) {
                        navigatePrevious()
                    } else {
                        navigateNext()
                    }
                    return .handled
                }
                .onKeyPress(.escape) {
                    closeSearch()
                    return .handled
                }
                .onChange(of: state.needle) { _, newValue in
                    scheduleSearch(newValue)
                }

            // Match count
            if !state.matchDisplay.isEmpty {
                Text(state.matchDisplay)
                    .font(AppFonts.badge)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            // Navigation buttons
            Button { navigatePrevious() } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.plain)
            .help("Previous match (Shift+Return)")

            Button { navigateNext() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.plain)
            .help("Next match (Return)")

            Button { closeSearch() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadius)
                .fill(AppPalette.overlay)
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadius)
                .strokeBorder(AppPalette.border, lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .onAppear { isTextFieldFocused = true }
    }

    // MARK: - Search Logic

    private func scheduleSearch(_ needle: String) {
        debounceTask?.cancel()

        if needle.isEmpty {
            // Clear search immediately
            performAction("end_search")
            searchState?.total = nil
            searchState?.selected = nil
            return
        }

        if needle.count >= 3 {
            // Immediate search for >= 3 chars
            performAction("search:\(needle)")
        } else {
            // Debounce short queries
            debounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                performAction("search:\(needle)")
            }
        }
    }

    private func navigateNext() {
        performAction("navigate_search:next")
    }

    private func navigatePrevious() {
        performAction("navigate_search:previous")
    }

    private func closeSearch() {
        debounceTask?.cancel()
        performAction("end_search")
        workspace.endSearch(paneID: paneID)
        refocusTerminal()
    }

    private func performAction(_ action: String) {
        ghosttyManager.terminalView(for: paneID)?.performBindingAction(action)
    }

    private func refocusTerminal() {
        _ = ghosttyManager.focusPane(paneID)
    }
}
