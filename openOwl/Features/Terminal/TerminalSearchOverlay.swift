import SwiftUI

/// Floating search bar overlaid on a terminal pane.
/// Debounces short queries (< 3 chars) by 300ms, fires immediately for >= 3 chars.
struct TerminalSearchOverlay: View {
    let paneID: UUID
    /// Whether the owning pane currently has terminal focus.
    /// When focus moves to another pane, the search bar auto-closes.
    let isFocused: Bool
    @Environment(TerminalWorkspaceStore.self) private var workspace
    @Environment(GhosttyAppManager.self) private var ghosttyManager
    @FocusState private var isTextFieldFocused: Bool

    private var searchState: TerminalSearchState? {
        workspace.paneSearchStates[paneID]
    }

    var body: some View {
        if let state = searchState, state.isSearching {
            searchBar(state)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onChange(of: isFocused) { _, focused in
                    // Auto-close when another pane steals terminal focus.
                    // Do NOT refocus this pane — the new pane already has focus.
                    if !focused { closeSearch(refocus: false) }
                }
        }
    }

    @ViewBuilder
    private func searchBar(_ state: TerminalSearchState) -> some View {
        HStack(spacing: 6) {
            // Search field
            // .onSubmit fires only when the TextField is the active text input,
            // unlike .onKeyPress which can intercept Return even when SwiftUI's
            // @FocusState is out of sync with AppKit's firstResponder in hybrid apps.
            // Esc is handled by AppDelegate's NSEvent local monitor (always works).
            TextField("Search...", text: Bindable(state).needle)
                .textFieldStyle(.plain)
                .font(AppFonts.body)
                .focused($isTextFieldFocused)
                .frame(minWidth: 120, maxWidth: 200)
                .onSubmit {
                    if NSEvent.modifierFlags.contains(.shift) {
                        navigatePrevious()
                    } else {
                        navigateNext()
                    }
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
        searchState?.debounceTask?.cancel()

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
            // Debounce short queries; task stored on the shared state so the
            // AppDelegate Esc path (endSearch) can cancel it too.
            searchState?.debounceTask = Task { @MainActor in
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

    private func closeSearch(refocus: Bool = true) {
        searchState?.debounceTask?.cancel()
        performAction("end_search")
        workspace.endSearch(paneID: paneID)
        if refocus { refocusTerminal() }
    }

    private func performAction(_ action: String) {
        guard let view = ghosttyManager.terminalView(for: paneID) else {
            // Pane unregistered (e.g., closed while search was active) — ghostty surface
            // teardown handles cleanup, so this is benign. Log for future diagnostics.
            NSLog("openOwl: [TerminalSearch] performAction skipped (pane unregistered) pane=%@ action=%@",
                  paneID.uuidString, action)
            return
        }
        view.performBindingAction(action)
    }

    private func refocusTerminal() {
        _ = ghosttyManager.focusPane(paneID)
    }
}
