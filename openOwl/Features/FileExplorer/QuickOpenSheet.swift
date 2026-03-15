import AppKit
import SwiftUI

// MARK: - Search field (NSTextField + delegate handles arrow keys via Binding)

private struct QuickOpenSearchField: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedIndex: Int
    var matchCount: Int
    var onSubmit: () -> Void
    var onEscape: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.font = .systemFont(ofSize: 14)
        field.placeholderString = "Go to File"
        field.isBordered = false
        field.focusRingType = .none
        field.backgroundColor = .clear
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
        context.coordinator.selectedIndex = $selectedIndex
        context.coordinator.matchCount = matchCount
        context.coordinator.onEscape = onEscape
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            selectedIndex: $selectedIndex,
            matchCount: matchCount,
            onSubmit: onSubmit,
            onEscape: onEscape
        )
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var selectedIndex: Binding<Int>
        var matchCount: Int
        var onSubmit: () -> Void
        var onEscape: () -> Void

        init(
            text: Binding<String>,
            selectedIndex: Binding<Int>,
            matchCount: Int,
            onSubmit: @escaping () -> Void,
            onEscape: @escaping () -> Void
        ) {
            self.text = text
            self.selectedIndex = selectedIndex
            self.matchCount = matchCount
            self.onSubmit = onSubmit
            self.onEscape = onEscape
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy sel: Selector
        ) -> Bool {
            switch sel {
            case #selector(NSResponder.insertNewline(_:)):
                onSubmit()
                return true
            case #selector(NSResponder.moveDown(_:)):
                moveSelection(1)
                return true
            case #selector(NSResponder.moveUp(_:)):
                moveSelection(-1)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                onEscape()
                return true
            default:
                return false
            }
        }

        private func moveSelection(_ delta: Int) {
            let count = min(matchCount, 50)
            guard count > 0 else { return }
            selectedIndex.wrappedValue = (selectedIndex.wrappedValue + delta + count) % count
        }
    }
}

// MARK: - Quick Open Panel

struct QuickOpenPanel: View {
    @EnvironmentObject private var store: FileExplorerStore
    @EnvironmentObject private var navigationStore: AppNavigationStore
    @EnvironmentObject private var gitStore: GitChangesStore
    @State private var selectedIndex: Int = 0

    private var matches: [FileQuickOpenMatch] { store.quickOpenMatches }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                QuickOpenSearchField(
                    text: $store.quickOpenQuery,
                    selectedIndex: $selectedIndex,
                    matchCount: matches.count,
                    onSubmit: { openSelected() },
                    onEscape: { store.dismissQuickOpen() }
                )
                .frame(height: 22)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if matches.isEmpty && !store.quickOpenQuery.isEmpty {
                Text("No matching files")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(matches.prefix(50).enumerated()), id: \.element.id) { index, match in
                                QuickOpenRow(
                                    node: match.node,
                                    relativePath: store.relativePath(for: match.node),
                                    matchedIndices: match.matchedIndices,
                                    isSelected: index == selectedIndex
                                )
                                .id(index)
                                .contentShape(Rectangle())
                                .onTapGesture { openMatch(match) }
                            }
                        }
                    }
                    .frame(maxHeight: 340)
                    .onChange(of: selectedIndex) { _, newIndex in
                        withAnimation(.none) { proxy.scrollTo(newIndex, anchor: .center) }
                    }
                }
            }
        }
        .frame(width: 500)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
        .onAppear {
            store.quickOpenQuery = ""
            store.updateQuickOpenResults()
            selectedIndex = 0
        }
        .onChange(of: store.quickOpenQuery) { _, _ in
            store.updateQuickOpenResults()
            selectedIndex = 0
        }
    }

    private func openSelected() {
        let items = Array(matches.prefix(50))
        guard selectedIndex < items.count else { return }
        openMatch(items[selectedIndex])
    }

    private func openMatch(_ match: FileQuickOpenMatch) {
        store.selectNode(match.node.id)
        store.dismissQuickOpen()
        if store.isChangedFile(match.node) {
            navigationStore.activeTab = .gitChanges
            gitStore.openDiff(forFileURL: match.node.url)
        } else {
            navigationStore.activeTab = .fileExplorer
        }
    }
}

// MARK: - Row

private struct QuickOpenRow: View {
    let node: FileExplorerNode
    let relativePath: String
    let matchedIndices: [Int]
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 12))
                .foregroundStyle(iconColor)
                .frame(width: 16)

            highlightedName
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(relativePath)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
    }

    private var highlightedName: Text {
        let matchSet = Set(matchedIndices)
        let chars = Array(node.name)
        var result = Text("")
        for (i, ch) in chars.enumerated() {
            let piece = Text(String(ch))
                .font(.system(size: 13, weight: matchSet.contains(i) ? .bold : .regular))
                .foregroundColor(matchSet.contains(i) ? Color.accentColor : .primary)
            result = result + piece
        }
        return result
    }

    private var iconName: String {
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

    private var iconColor: Color {
        if node.isDirectory { return Color(nsColor: .systemBlue) }
        let ext = node.url.pathExtension.lowercased()
        switch ext {
        case "swift": return Color(nsColor: .systemOrange)
        case "js", "ts", "tsx", "jsx": return Color(nsColor: .systemYellow)
        case "py": return Color(nsColor: .systemGreen)
        case "json", "yml", "yaml": return Color(nsColor: .systemPurple)
        default: return .secondary
        }
    }
}
