import AppKit
import SwiftUI

struct FileExplorerView: View {
    @EnvironmentObject private var store: FileExplorerStore
    @EnvironmentObject private var projectStore: ProjectStore
    @EnvironmentObject private var gitStore: GitChangesStore
    @EnvironmentObject private var navigationStore: AppNavigationStore
    @FocusState private var quickOpenInputFocused: Bool

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { store.selectedNodeID },
            set: { store.selectNode($0) }
        )
    }

    private var quickOpenSelectionBinding: Binding<String?> {
        Binding(
            get: { store.quickOpenSelectionID },
            set: { store.selectQuickOpenResult($0) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            HSplitView {
                treePanel
                    .frame(minWidth: 280, idealWidth: 340)

                previewPanel
                    .frame(minWidth: 360)
            }
        }
        .onAppear {
            store.setProject(projectStore.activeProjectURL)
        }
        .onChange(of: projectStore.activeProjectID) { _, _ in
            store.setProject(projectStore.activeProjectURL)
        }
        .sheet(isPresented: $store.isQuickOpenPresented, onDismiss: {
            store.dismissQuickOpen()
        }) {
            quickOpenSheet
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(store.projectURL?.path ?? "No project selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Button("Choose Project") {
                    projectStore.openProjectPicker()
                }

                Button("Quick Open") {
                    store.presentQuickOpen()
                }
                .keyboardShortcut("p", modifiers: [.command])
                .disabled(store.rootNodes.isEmpty)
                .help("Quick open file (Cmd+P)")

                Button {
                    store.refreshNow()
                } label: {
                    if store.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .help("Refresh file tree")
                .disabled(store.isRefreshing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if let errorMessage = store.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption)
                    Text(errorMessage)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Button("Dismiss") {
                        store.errorMessage = nil
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                }
                .foregroundStyle(.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.08))
            }
        }
    }

    private var treePanel: some View {
        Group {
            if store.rootNodes.isEmpty {
                VStack {
                    Spacer()
                    Text("No files")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                List(selection: selectionBinding) {
                    OutlineGroup(store.rootNodes, children: \.children) { node in
                        row(for: node)
                            .tag(node.id)
                            .contentShape(Rectangle())
                            .contextMenu {
                                contextMenu(for: node)
                            }
                            .onDrag {
                                NSItemProvider(object: node.url as NSURL)
                            }
                            .onTapGesture {
                                if store.isChangedFile(node) {
                                    openDiff(for: node)
                                }
                            }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(store.selectedNode?.url.path ?? "Preview")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            switch store.previewState {
            case .none:
                placeholder("Select a file to preview")

            case .directory(let path, let itemCount):
                VStack(alignment: .leading, spacing: 8) {
                    Text("Directory")
                        .font(.headline)
                    Text(path)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("Items: \(itemCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            case .text(let content, let truncated):
                ScrollView([.vertical, .horizontal]) {
                    Text(highlightedPreviewText(content))
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .overlay(alignment: .bottomTrailing) {
                    if truncated {
                        Text("Preview truncated")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(8)
                    }
                }

            case .binary:
                placeholder("Binary file cannot be previewed")

            case .unavailable(let message):
                placeholder(message)
            }
        }
    }

    private var quickOpenSheet: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                TextField("Search files", text: $store.quickOpenQuery)
                    .textFieldStyle(.roundedBorder)
                    .focused($quickOpenInputFocused)
                    .onSubmit {
                        openQuickOpenSelection()
                    }

                Button("Open") {
                    openQuickOpenSelection()
                }
                .disabled(store.quickOpenMatches.isEmpty)

                Button("Cancel") {
                    store.dismissQuickOpen()
                }
            }

            if store.quickOpenMatches.isEmpty {
                VStack {
                    Spacer()
                    Text("No matching files")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                List(selection: quickOpenSelectionBinding) {
                    ForEach(store.quickOpenMatches) { match in
                        quickOpenResultRow(for: match.node)
                            .tag(match.id)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                openQuickOpenNode(match.node)
                            }
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(14)
        .frame(minWidth: 560, minHeight: 420)
        .onAppear {
            store.syncQuickOpenSelection()
            DispatchQueue.main.async {
                quickOpenInputFocused = true
            }
        }
        .onChange(of: store.quickOpenQuery) { _, _ in
            store.syncQuickOpenSelection()
        }
    }

    private func row(for node: FileExplorerNode) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbolName(for: node))
                .foregroundStyle(node.isDirectory ? Color.accentColor : .secondary)

            Text(node.name)
                .lineLimit(1)
                .foregroundStyle(gitColor(for: node.gitState) ?? Color.primary)

            Spacer(minLength: 8)

            if let gitState = node.gitState {
                gitStateBadge(gitState)
            }
        }
        .font(.system(size: 12))
    }

    private func quickOpenResultRow(for node: FileExplorerNode) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: symbolName(for: node))
                    .foregroundStyle(.secondary)

                Text(node.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(gitColor(for: node.gitState) ?? Color.primary)

                Spacer(minLength: 8)

                if let gitState = node.gitState {
                    gitStateBadge(gitState)
                }
            }

            Text(store.relativePath(for: node))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func contextMenu(for node: FileExplorerNode) -> some View {
        if store.isChangedFile(node) {
            Button("Open Diff") {
                openDiff(for: node)
            }
        }

        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([node.url])
        }

        Button("Open in Terminal") {
            store.openInTerminal(node)
        }

        Button("Copy Path") {
            store.copyPath(node.url)
        }
    }

    private func openDiff(for node: FileExplorerNode) {
        guard !node.isDirectory else { return }
        navigationStore.selection = .gitChanges
        gitStore.openDiff(forFileURL: node.url)
    }

    private func openQuickOpenSelection() {
        guard let node = store.openQuickOpenSelection() else { return }
        if store.isChangedFile(node) {
            openDiff(for: node)
        }
    }

    private func openQuickOpenNode(_ node: FileExplorerNode) {
        store.selectNode(node.id)
        store.dismissQuickOpen()
        if store.isChangedFile(node) {
            openDiff(for: node)
        }
    }

    private func placeholder(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func symbolName(for node: FileExplorerNode) -> String {
        if node.isDirectory {
            return "folder"
        }

        let ext = node.url.pathExtension.lowercased()
        switch ext {
        case "swift":
            return "swift"
        case "md", "txt", "log":
            return "doc.text"
        case "json", "yml", "yaml", "toml", "plist":
            return "curlybraces"
        case "png", "jpg", "jpeg", "gif", "webp", "svg":
            return "photo"
        case "sh", "zsh", "bash":
            return "terminal"
        case "js", "ts", "tsx", "jsx":
            return "chevron.left.forwardslash.chevron.right"
        default:
            return "doc"
        }
    }

    private func gitColor(for state: FileGitState?) -> Color? {
        guard let state else { return nil }

        switch state {
        case .added:
            return .green
        case .modified:
            return .orange
        case .deleted:
            return .red
        case .renamed:
            return .blue
        case .conflicted:
            return Color(nsColor: .systemPink)
        }
    }

    private func gitStateBadge(_ state: FileGitState) -> some View {
        let color = gitColor(for: state) ?? .secondary

        return Text(state.shortCode)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(color.opacity(0.16))
            )
    }

    private var selectedFileExtension: String? {
        guard let extensionName = store.selectedNode?.url.pathExtension.lowercased(),
              !extensionName.isEmpty else { return nil }
        return extensionName
    }

    private func highlightedPreviewText(_ content: String) -> AttributedString {
        let sourceText = content.isEmpty ? " " : content
        var attributed = AttributedString(sourceText)
        attributed.foregroundColor = .primary

        guard sourceText.count <= 120_000 else {
            return attributed
        }
        guard let fileExtension = selectedFileExtension else {
            return attributed
        }

        applyPreviewSyntaxHighlight(
            to: &attributed,
            sourceText: sourceText,
            fileExtension: fileExtension
        )
        return attributed
    }

    private func applyPreviewSyntaxHighlight(
        to attributed: inout AttributedString,
        sourceText: String,
        fileExtension: String
    ) {
        if let commentPattern = previewCommentPattern(for: fileExtension) {
            applyPreviewRegex(
                pattern: commentPattern,
                color: .secondary,
                to: &attributed,
                sourceText: sourceText
            )
        }

        applyPreviewRegex(
            pattern: #"\"([^\"\\]|\\.)*\"|'([^'\\]|\\.)*'"#,
            color: .orange,
            to: &attributed,
            sourceText: sourceText
        )

        guard let keywordPattern = previewKeywordPattern(for: fileExtension) else { return }
        applyPreviewRegex(
            pattern: keywordPattern,
            color: .blue,
            to: &attributed,
            sourceText: sourceText
        )
    }

    private func applyPreviewRegex(
        pattern: String,
        color: Color,
        to attributed: inout AttributedString,
        sourceText: String
    ) {
        guard !sourceText.isEmpty else { return }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return }

        let nsRange = NSRange(sourceText.startIndex..<sourceText.endIndex, in: sourceText)
        regex.matches(in: sourceText, range: nsRange).forEach { match in
            guard let sourceRange = Range(match.range, in: sourceText),
                  let attributedRange = Range(sourceRange, in: attributed) else { return }
            attributed[attributedRange].foregroundColor = color
        }
    }

    private func previewKeywordPattern(for fileExtension: String) -> String? {
        switch fileExtension {
        case "swift":
            return #"\b(import|let|var|func|struct|class|enum|protocol|extension|if|else|for|while|switch|case|default|guard|return|defer|do|catch|throw|throws|rethrows|try|async|await|actor|where|in)\b"#
        case "ts", "tsx", "js", "jsx":
            return #"\b(import|from|export|const|let|var|function|class|interface|type|extends|implements|if|else|for|while|switch|case|default|return|try|catch|throw|async|await|new|typeof)\b"#
        case "py":
            return #"\b(import|from|as|def|class|if|elif|else|for|while|return|try|except|finally|raise|with|lambda|async|await|yield|pass|break|continue)\b"#
        case "go":
            return #"\b(package|import|func|type|struct|interface|var|const|if|else|for|switch|case|default|return|defer|go|range|map|chan|select)\b"#
        case "rs":
            return #"\b(use|mod|fn|struct|enum|impl|trait|let|mut|if|else|for|while|loop|match|return|pub|crate|self|super|async|await|move)\b"#
        case "java", "kt":
            return #"\b(import|package|class|interface|enum|public|private|protected|static|final|void|var|val|fun|if|else|for|while|switch|case|return|try|catch|throw|new)\b"#
        case "c", "h", "cpp", "hpp", "cc":
            return #"\b(include|define|typedef|struct|enum|class|if|else|for|while|switch|case|return|static|const|void|int|char|float|double|bool|auto|template|namespace)\b"#
        case "sh", "zsh", "bash":
            return #"\b(if|then|else|fi|for|in|do|done|while|case|esac|function|return|export|local)\b"#
        default:
            return nil
        }
    }

    private func previewCommentPattern(for fileExtension: String) -> String? {
        switch fileExtension {
        case "swift", "ts", "tsx", "js", "jsx", "go", "rs", "java", "kt", "c", "h", "cpp", "hpp", "cc":
            return #"//.*$"#
        case "py", "sh", "zsh", "bash", "rb", "yaml", "yml", "toml":
            return #"#.*$"#
        default:
            return nil
        }
    }
}
