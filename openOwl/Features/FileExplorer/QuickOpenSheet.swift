import SwiftUI

struct QuickOpenSheet: View {
    @EnvironmentObject private var store: FileExplorerStore
    @EnvironmentObject private var navigationStore: AppNavigationStore
    @EnvironmentObject private var gitStore: GitChangesStore
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                    TextField("Search files", text: $store.quickOpenQuery)
                        .textFieldStyle(.plain)
                        .focused($inputFocused)
                        .onSubmit { openSelection() }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

                Button("Open") { openSelection() }
                    .disabled(store.quickOpenMatches.isEmpty)
                Button("Cancel") { store.dismissQuickOpen() }
            }

            if store.quickOpenMatches.isEmpty {
                Spacer()
                Text("No matching files").foregroundStyle(.secondary)
                Spacer()
            } else {
                List(selection: Binding(
                    get: { store.quickOpenSelectionID },
                    set: { store.selectQuickOpenResult($0) }
                )) {
                    ForEach(store.quickOpenMatches) { match in
                        HStack(spacing: 6) {
                            Image(systemName: fileIcon(for: match.node))
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                            Text(match.node.name)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            Spacer()
                            Text(store.relativePath(for: match.node))
                                .font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
                        }
                        .tag(match.id)
                        .onTapGesture(count: 2) {
                            store.selectNode(match.node.id)
                            navigationStore.activeTab = .fileExplorer
                            store.dismissQuickOpen()
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(14)
        .frame(minWidth: 560, minHeight: 420)
        .onAppear {
            store.updateQuickOpenResults()
            store.syncQuickOpenSelection()
            DispatchQueue.main.async { inputFocused = true }
        }
        .onChange(of: store.quickOpenQuery) { _, _ in
            store.updateQuickOpenResults()
        }
        .onChange(of: store.quickOpenResults) { _, _ in
            store.syncQuickOpenSelection()
        }
    }

    private func openSelection() {
        guard let node = store.openQuickOpenSelection() else { return }
        if store.isChangedFile(node) {
            navigationStore.activeTab = .gitChanges
            gitStore.openDiff(forFileURL: node.url)
        } else {
            navigationStore.activeTab = .fileExplorer
        }
    }

    private func fileIcon(for node: FileExplorerNode) -> String {
        if node.isDirectory { return "folder.fill" }
        let ext = node.url.pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "md", "txt", "log": return "doc.text"
        case "json", "yml", "yaml", "toml", "plist": return "curlybraces"
        case "png", "jpg", "jpeg", "gif", "webp", "svg": return "photo"
        case "sh", "zsh", "bash": return "terminal"
        case "js", "ts", "tsx", "jsx": return "chevron.left.forwardslash.chevron.right"
        default: return "doc"
        }
    }
}
