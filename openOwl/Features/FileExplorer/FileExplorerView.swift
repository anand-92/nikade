import AppKit
import SwiftUI

struct FileExplorerView: View {
    @EnvironmentObject private var store: FileExplorerStore
    @EnvironmentObject private var projectStore: ProjectStore
    @EnvironmentObject private var gitStore: GitChangesStore
    @EnvironmentObject private var navigationStore: AppNavigationStore
    @State private var expandedIDs: Set<String> = []
    @State private var selectedIDs: Set<String> = []
    @State private var lastClickedID: String?
    @State private var renamingNodeID: String?
    @State private var renameText: String = ""
    @FocusState private var quickOpenInputFocused: Bool
    @FocusState private var renameFieldFocused: Bool

    var body: some View {
        HSplitView {
            treePanel
                .frame(minWidth: 200)

            previewPanel
                .frame(minWidth: 300)
        }
        .onAppear {
            store.setProject(projectStore.activeProjectURL)
            expandTopLevel()
        }
        .onChange(of: projectStore.activeProjectID) { _, _ in
            store.setProject(projectStore.activeProjectURL)
            expandedIDs.removeAll()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { expandTopLevel() }
        }
        .sheet(isPresented: $store.isQuickOpenPresented, onDismiss: {
            store.dismissQuickOpen()
        }) {
            quickOpenSheet
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleFileDrop(providers)
        }
    }

    private func expandTopLevel() {
        for node in store.rootNodes where node.isDirectory {
            expandedIDs.insert(node.id)
        }
    }

    // MARK: - Tree Panel

    private var treePanel: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("EXPLORER")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button { store.presentQuickOpen() } label: {
                    Image(systemName: "magnifyingglass").font(.system(size: 11))
                }
                .buttonStyle(.plain).help("Quick Open (⌘P)")
                .keyboardShortcut("p", modifiers: [.command])
                .disabled(store.rootNodes.isEmpty)

                Button { store.refreshNow() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11))
                }
                .buttonStyle(.plain).help("Refresh")
                .disabled(store.isRefreshing)
            }
            .padding(.horizontal, 12)
            .frame(height: AppConstants.headerHeight)

            Divider()

            if let errorMessage = store.errorMessage {
                HStack {
                    Text(errorMessage).font(.system(size: 10)).lineLimit(1)
                    Spacer()
                    Button { store.errorMessage = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 8))
                    }.buttonStyle(.plain)
                }
                .foregroundStyle(.red)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.red.opacity(0.08))
            }

            if store.rootNodes.isEmpty {
                Spacer()
                Text("No files").foregroundStyle(.secondary).font(.system(size: 12))
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(flattenedTree, id: \.node.id) { item in
                            FileTreeRowView(
                                node: item.node,
                                depth: item.depth,
                                isExpanded: expandedIDs.contains(item.node.id),
                                isSelected: selectedIDs.contains(item.node.id),
                                selectedCount: selectedIDs.count,
                                onSelect: { handleFileClick(item.node) },
                                onStage: { stageFiles(from: item.node) },
                                onDiscard: { discardFiles(from: item.node) },
                                onOpenDiff: { openDiff(item.node) },
                                onCopy: { copySelected() },
                                onCut: { cutSelected() },
                                onPaste: { pasteIntoSelected() },
                                onDelete: { deleteSelected() },
                                onRename: { startRename() },
                                isRenaming: renamingNodeID == item.node.id,
                                renameText: $renameText,
                                onCommitRename: { commitRename() },
                                onDropInto: item.node.isDirectory ? { providers in
                                    handleFileDropInto(item.node.url, providers: providers)
                                } : nil
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func handleFileClick(_ node: FileExplorerNode) {
        let modifiers = NSEvent.modifierFlags

        if node.isDirectory && !modifiers.contains(.command) && !modifiers.contains(.shift) {
            // Normal click on folder: toggle expand + select
            if expandedIDs.contains(node.id) {
                expandedIDs.remove(node.id)
            } else {
                expandedIDs.insert(node.id)
            }
            selectedIDs = [node.id]
            lastClickedID = node.id
            store.selectNode(node.id)
            return
        }

        if modifiers.contains(.command) {
            if selectedIDs.contains(node.id) { selectedIDs.remove(node.id) }
            else { selectedIDs.insert(node.id) }
        } else if modifiers.contains(.shift), let lastID = lastClickedID {
            let items = flattenedTree
            if let fromIdx = items.firstIndex(where: { $0.node.id == lastID }),
               let toIdx = items.firstIndex(where: { $0.node.id == node.id }) {
                let range = min(fromIdx, toIdx)...max(fromIdx, toIdx)
                for i in range { selectedIDs.insert(items[i].node.id) }
            }
        } else {
            selectedIDs = [node.id]
        }

        lastClickedID = node.id
        store.selectNode(node.id)
    }

    private func stageFiles(from node: FileExplorerNode) {
        let targets = selectedIDs.count > 1
            ? flattenedTree.filter { selectedIDs.contains($0.node.id) && $0.node.gitState != nil }.map { store.relativePath(for: $0.node) }
            : (node.gitState != nil ? [store.relativePath(for: node)] : [])
        guard !targets.isEmpty else { return }
        gitStore.stage(paths: targets)
    }

    private func discardFiles(from node: FileExplorerNode) {
        if selectedIDs.count > 1 {
            let targets = flattenedTree.filter { selectedIDs.contains($0.node.id) && $0.node.gitState != nil }
            for t in targets { gitStore.discardByPath(store.relativePath(for: t.node)) }
        } else if node.gitState != nil {
            gitStore.discardByPath(store.relativePath(for: node))
        }
    }

    private func openDiff(_ node: FileExplorerNode) {
        guard !node.isDirectory else { return }
        navigationStore.activeTab = .gitChanges
        gitStore.openDiff(forFileURL: node.url)
    }

    // MARK: - Keyboard Shortcuts

    func copySelected() {
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        store.copyFiles(urls)
    }

    func cutSelected() {
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        store.cutFiles(urls)
    }

    func pasteIntoSelected() {
        let targetDir: URL
        if let id = selectedIDs.first, let node = store.nodeIndex[id] {
            targetDir = node.isDirectory ? node.url : node.url.deletingLastPathComponent()
        } else {
            guard let projectURL = store.projectURL else { return }
            targetDir = projectURL
        }
        store.pasteFiles(into: targetDir)
    }

    func deleteSelected() {
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        store.deleteNodes(urls)
        selectedIDs.removeAll()
    }

    func startRename() {
        guard selectedIDs.count == 1, let id = selectedIDs.first,
              let node = store.nodeIndex[id] else { return }
        renamingNodeID = id
        renameText = node.name
        renameFieldFocused = true
    }

    func commitRename() {
        guard let id = renamingNodeID, let node = store.nodeIndex[id] else {
            renamingNodeID = nil
            return
        }
        store.renameNode(node, to: renameText)
        renamingNodeID = nil
    }

    private var selectedURLs: [URL] {
        flattenedTree
            .filter { selectedIDs.contains($0.node.id) }
            .map(\.node.url)
    }

    // MARK: - Drag & Drop

    private func handleFileDropInto(_ targetDir: URL, providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                let dest = targetDir.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.copyItem(at: url, to: dest)
                DispatchQueue.main.async { self.store.refreshNow() }
            }
            handled = true
        }
        return handled
    }

    private func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        let targetDir: URL
        if let id = selectedIDs.first, let node = store.nodeIndex[id], node.isDirectory {
            targetDir = node.url
        } else {
            guard let projectURL = store.projectURL else { return false }
            targetDir = projectURL
        }

        var handled = false
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                let dest = targetDir.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.copyItem(at: url, to: dest)
                DispatchQueue.main.async { self.store.refreshNow() }
            }
            handled = true
        }
        return handled
    }

    // MARK: - Flatten Tree

    private struct FlatTreeItem {
        let node: FileExplorerNode
        let depth: Int
    }

    private var flattenedTree: [FlatTreeItem] {
        var result: [FlatTreeItem] = []
        func walk(_ nodes: [FileExplorerNode], depth: Int) {
            for node in nodes {
                result.append(FlatTreeItem(node: node, depth: depth))
                if node.isDirectory && expandedIDs.contains(node.id), let children = node.children {
                    walk(children, depth: depth + 1)
                }
            }
        }
        walk(store.rootNodes, depth: 0)
        return result
    }

    // MARK: - Preview Panel

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                if let node = store.selectedNode {
                    Image(systemName: fileIcon(for: node))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(store.relativePath(for: node))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                } else {
                    Text("Preview")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if store.selectedNode != nil, store.isChangedFile(store.selectedNode!) {
                    Button("Open Diff") {
                        if let node = store.selectedNode {
                            navigationStore.activeTab = .gitChanges
                            gitStore.openDiff(forFileURL: node.url)
                        }
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: AppConstants.headerHeight)

            Divider()

            switch store.previewState {
            case .none:
                Spacer()
                Text("Select a file to preview")
                    .foregroundStyle(.secondary).font(.system(size: 12))
                    .frame(maxWidth: .infinity)
                Spacer()

            case .directory(let path, let itemCount):
                VStack(alignment: .leading, spacing: 6) {
                    Text(path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("\(itemCount) items")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            case .text(let content, let truncated):
                ScrollView([.vertical, .horizontal]) {
                    Text(highlightedPreviewText(content))
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .overlay(alignment: .bottomTrailing) {
                    if truncated {
                        Text("Truncated")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .padding(6)
                    }
                }

            case .binary:
                Spacer()
                Text("Binary file").foregroundStyle(.secondary).font(.system(size: 12))
                    .frame(maxWidth: .infinity)
                Spacer()

            case .unavailable(let message):
                Spacer()
                Text(message).foregroundStyle(.secondary).font(.system(size: 12))
                    .frame(maxWidth: .infinity)
                Spacer()
            }
        }
    }

    // MARK: - Quick Open

    private var quickOpenSheet: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                TextField("Search files", text: $store.quickOpenQuery)
                    .textFieldStyle(.roundedBorder)
                    .focused($quickOpenInputFocused)
                    .onSubmit { openQuickOpenSelection() }

                Button("Open") { openQuickOpenSelection() }
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
                        .onTapGesture(count: 2) { openQuickOpenNode(match.node) }
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(14)
        .frame(minWidth: 560, minHeight: 420)
        .onAppear {
            store.syncQuickOpenSelection()
            DispatchQueue.main.async { quickOpenInputFocused = true }
        }
        .onChange(of: store.quickOpenQuery) { _, _ in store.syncQuickOpenSelection() }
    }

    private func openQuickOpenSelection() {
        guard let node = store.openQuickOpenSelection() else { return }
        if store.isChangedFile(node) {
            navigationStore.activeTab = .gitChanges
            gitStore.openDiff(forFileURL: node.url)
        }
    }

    private func openQuickOpenNode(_ node: FileExplorerNode) {
        store.selectNode(node.id)
        store.dismissQuickOpen()
    }

    // MARK: - Helpers

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

    // MARK: - Syntax Highlighting

    private var selectedFileExtension: String? {
        guard let ext = store.selectedNode?.url.pathExtension.lowercased(), !ext.isEmpty else { return nil }
        return ext
    }

    private func highlightedPreviewText(_ content: String) -> AttributedString {
        let text = content.isEmpty ? " " : content
        var attributed = AttributedString(text)
        attributed.foregroundColor = .primary
        guard text.count <= 120_000, let ext = selectedFileExtension else { return attributed }

        if let cp = commentPattern(for: ext) { applyRegex(cp, color: .secondary, to: &attributed, text: text) }
        applyRegex(#"\"([^\"\\]|\\.)*\"|'([^'\\]|\\.)*'"#, color: .orange, to: &attributed, text: text)
        if let kp = keywordPattern(for: ext) { applyRegex(kp, color: .blue, to: &attributed, text: text) }
        return attributed
    }

    private func applyRegex(_ pattern: String, color: Color, to attributed: inout AttributedString, text: String) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        regex.matches(in: text, range: nsRange).forEach { match in
            guard let sr = Range(match.range, in: text), let ar = Range(sr, in: attributed) else { return }
            attributed[ar].foregroundColor = color
        }
    }

    private func keywordPattern(for ext: String) -> String? {
        switch ext {
        case "swift": return #"\b(import|let|var|func|struct|class|enum|protocol|extension|if|else|for|while|switch|case|default|guard|return|defer|do|catch|throw|throws|try|async|await|actor|where|in)\b"#
        case "ts", "tsx", "js", "jsx": return #"\b(import|from|export|const|let|var|function|class|interface|type|if|else|for|while|switch|case|default|return|try|catch|throw|async|await|new|typeof)\b"#
        case "py": return #"\b(import|from|as|def|class|if|elif|else|for|while|return|try|except|finally|raise|with|lambda|async|await|yield)\b"#
        case "go": return #"\b(package|import|func|type|struct|interface|var|const|if|else|for|switch|case|default|return|defer|go|range|map|chan|select)\b"#
        case "rs": return #"\b(use|mod|fn|struct|enum|impl|trait|let|mut|if|else|for|while|loop|match|return|pub|async|await|move)\b"#
        case "c", "h", "cpp", "hpp", "cc": return #"\b(include|define|typedef|struct|enum|class|if|else|for|while|switch|case|return|static|const|void|int|char|float|double|bool|auto)\b"#
        case "sh", "zsh", "bash": return #"\b(if|then|else|fi|for|in|do|done|while|case|esac|function|return|export|local)\b"#
        default: return nil
        }
    }

    private func commentPattern(for ext: String) -> String? {
        switch ext {
        case "swift", "ts", "tsx", "js", "jsx", "go", "rs", "java", "kt", "c", "h", "cpp", "hpp", "cc": return #"//.*$"#
        case "py", "sh", "zsh", "bash", "rb", "yaml", "yml", "toml": return #"#.*$"#
        default: return nil
        }
    }
}

// MARK: - File Tree Row (flat, no recursion — contextMenu works reliably)

private struct FileTreeRowView: View {
    let node: FileExplorerNode
    let depth: Int
    let isExpanded: Bool
    let isSelected: Bool
    var selectedCount: Int = 0
    let onSelect: () -> Void
    var onStage: (() -> Void)?
    var onDiscard: (() -> Void)?
    var onOpenDiff: (() -> Void)?
    var onCopy: (() -> Void)?
    var onCut: (() -> Void)?
    var onPaste: (() -> Void)?
    var onDelete: (() -> Void)?
    var onRename: (() -> Void)?
    var isRenaming: Bool = false
    @Binding var renameText: String
    var onCommitRename: (() -> Void)?
    var onDropInto: (([NSItemProvider]) -> Bool)?

    private var isBatch: Bool { isSelected && selectedCount > 1 }

    @State private var hovering = false
    @State private var dropTargeted = false

    private var isChangedFile: Bool { !node.isDirectory && node.gitState != nil }
    private let indentPerLevel: CGFloat = 16

    var body: some View {
        HStack(spacing: 3) {
            if node.isDirectory {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 12)
            } else {
                Color.clear.frame(width: 12)
            }

            Image(systemName: nodeIcon)
                .font(.system(size: 10))
                .foregroundStyle(node.isDirectory ? Color(nsColor: .systemBlue) : .secondary)
                .frame(width: 14)

            if isRenaming {
                TextField("", text: $renameText, onCommit: { onCommitRename?() })
                    .font(.system(size: 11))
                    .textFieldStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(node.name)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(gitColor ?? Color.primary)
            }

            Spacer(minLength: 4)

            if hovering && isChangedFile {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .onTapGesture { onDiscard?() }
                    .help("Discard Changes")

                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .onTapGesture { onStage?() }
                    .help("Stage Changes")
            }

            if let state = node.gitState, !node.isDirectory {
                Text(state.shortCode)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(gitColor ?? .secondary)
            }
        }
        .padding(.leading, CGFloat(depth) * indentPerLevel + 4)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 22)
        .background(
            dropTargeted ? Color.accentColor.opacity(0.3)
            : isSelected ? Color.accentColor.opacity(0.2)
            : hovering ? Color.secondary.opacity(0.08)
            : Color.clear
        )
        .overlay(
            dropTargeted ? RoundedRectangle(cornerRadius: 2).stroke(Color.accentColor, lineWidth: 1) : nil
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 1) { onSelect() }
        .if(node.isDirectory) { view in
            view.onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                onDropInto?(providers) ?? false
            }
        }
        .contextMenu {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
            Divider()
            Button("Cut") { onCut?() }
            Button("Copy") { onCopy?() }
            Button("Paste") { onPaste?() }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(node.url.path, forType: .string)
            }
            Divider()
            Button("Rename") { onRename?() }
            Button("Delete", role: .destructive) { onDelete?() }

            if isChangedFile {
                Divider()
                Button("Open Changes") { onOpenDiff?() }
                Button(isBatch ? "Stage \(selectedCount) Files" : "Stage Changes") { onStage?() }
                Button(isBatch ? "Discard \(selectedCount) Files" : "Discard Changes") { onDiscard?() }
            }
        }
    }

    private var nodeIcon: String {
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

    private var gitColor: Color? {
        guard let state = node.gitState else { return nil }
        switch state {
        case .added: return Color(nsColor: .systemGreen)
        case .modified: return Color(nsColor: .systemYellow)
        case .deleted: return Color(nsColor: .systemRed)
        case .renamed: return Color(nsColor: .systemBlue)
        case .conflicted: return Color(nsColor: .systemPink)
        }
    }
}

// MARK: - Conditional View Modifier

private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
