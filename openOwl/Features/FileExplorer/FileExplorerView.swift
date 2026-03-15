import AppKit
import SwiftUI
import CodeEditSourceEditor
import CodeEditLanguages

let editorConfiguration = SourceEditorConfiguration(
    appearance: .init(
        theme: EditorTheme(
            text: .init(color: NSColor(calibratedWhite: 0.9, alpha: 1.0)),
            insertionPoint: NSColor(calibratedRed: 0.3, green: 0.6, blue: 1.0, alpha: 1.0),
            invisibles: .init(color: NSColor(calibratedWhite: 0.5, alpha: 0.3)),
            background: NSColor(calibratedRed: 0.15, green: 0.15, blue: 0.17, alpha: 1.0),
            lineHighlight: NSColor(calibratedRed: 0.2, green: 0.2, blue: 0.22, alpha: 1.0),
            selection: NSColor(calibratedRed: 0.25, green: 0.35, blue: 0.5, alpha: 0.4),
            keywords: .init(color: NSColor(calibratedRed: 0.8, green: 0.4, blue: 0.8, alpha: 1.0)),
            commands: .init(color: NSColor(calibratedRed: 0.4, green: 0.7, blue: 0.9, alpha: 1.0)),
            types: .init(color: NSColor(calibratedRed: 0.4, green: 0.8, blue: 0.7, alpha: 1.0)),
            attributes: .init(color: NSColor(calibratedRed: 0.7, green: 0.6, blue: 0.4, alpha: 1.0)),
            variables: .init(color: NSColor(calibratedRed: 0.5, green: 0.7, blue: 0.9, alpha: 1.0)),
            values: .init(color: NSColor(calibratedRed: 0.9, green: 0.7, blue: 0.4, alpha: 1.0)),
            numbers: .init(color: NSColor(calibratedRed: 0.9, green: 0.7, blue: 0.4, alpha: 1.0)),
            strings: .init(color: NSColor(calibratedRed: 0.9, green: 0.5, blue: 0.5, alpha: 1.0)),
            characters: .init(color: NSColor(calibratedRed: 0.9, green: 0.5, blue: 0.5, alpha: 1.0)),
            comments: .init(color: NSColor(calibratedRed: 0.5, green: 0.6, blue: 0.5, alpha: 1.0))
        ),
        font: .monospacedSystemFont(ofSize: 12, weight: .regular),
        wrapLines: true
    ),
    peripherals: .init(showMinimap: false)
)

struct FileExplorerView: View {
    @EnvironmentObject private var store: FileExplorerStore
    @EnvironmentObject private var projectStore: ProjectStore
    @EnvironmentObject private var gitStore: GitChangesStore
    @EnvironmentObject private var navigationStore: AppNavigationStore
    @FocusState private var quickOpenInputFocused: Bool

    // Code editor state
    @State private var editorText: String = ""
    @State private var editorState = SourceEditorState()
    @State private var editingFileURL: URL?
    @State private var loadingFileURL: URL?
    @State private var isEditorDirty = false
    @State private var isEditorLoading = false
    @State private var previewImage: NSImage?

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "webp", "heic", "heif", "ico", "svg", "icns"
    ]

    private var isImageFile: Bool {
        guard let ext = editingFileURL?.pathExtension.lowercased() else { return false }
        return Self.imageExtensions.contains(ext)
    }

    var body: some View {
        HStack(spacing: 0) {
            treePanel
                .frame(width: 240)

            Divider()

            editorPanel
        }
        .onAppear {
            store.setProject(projectStore.activeProjectURL)
        }
        .onChange(of: projectStore.activeProjectID) { _, _ in
            if isEditorDirty { saveCurrentFile() }
            store.setProject(projectStore.activeProjectURL)
            editingFileURL = nil
            loadingFileURL = nil
            previewImage = nil
            isEditorDirty = false
        }
        .onDisappear {
            if isEditorDirty { saveCurrentFile() }
        }
        .sheet(isPresented: $store.isQuickOpenPresented, onDismiss: {
            store.dismissQuickOpen()
        }) {
            quickOpenSheet
        }
        .background {
            Button("") { saveCurrentFile() }
                .keyboardShortcut("s", modifiers: [.command])
                .hidden()
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
                OutlineTreeView(
                    onSelectFile: { node in
                        store.selectNode(node.id)
                        loadFileIntoEditor(node)
                    },
                    onStage: { node in stageFile(node) },
                    onDiscard: { node in discardFile(node) },
                    onOpenDiff: { node in openDiff(node) },
                    onDelete: { urls in store.deleteNodes(urls) },
                    onRename: { node, newName in store.renameNode(node, to: newName) },
                    onCopy: { urls in store.copyFiles(urls) },
                    onCut: { urls in store.cutFiles(urls) },
                    onPaste: { targetDir in store.pasteFiles(into: targetDir) },
                    onCopyPath: { url in store.copyPath(url) },
                    onDropFiles: { targetDir, sourceURLs in
                        let fm = FileManager.default
                        for url in sourceURLs {
                            let dest = targetDir.appendingPathComponent(url.lastPathComponent)
                            try? fm.copyItem(at: url, to: dest)
                        }
                        store.refreshNow()
                    }
                )
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    // MARK: - Editor

    private func loadFileIntoEditor(_ node: FileExplorerNode) {
        guard !node.isDirectory else { return }
        let url = node.url
        if editingFileURL == url || loadingFileURL == url { return }
        if isEditorDirty { saveCurrentFile() }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        if fileSize > 10_000_000 {
            editingFileURL = nil
            loadingFileURL = nil
            previewImage = nil
            return
        }

        let ext = url.pathExtension.lowercased()
        let isImage = Self.imageExtensions.contains(ext)

        // Keep showing old editor while loading new content
        loadingFileURL = url
        isEditorLoading = true

        if isImage {
            Task.detached(priority: .userInitiated) {
                let image = NSImage(contentsOf: url)
                await MainActor.run {
                    guard loadingFileURL == url else { return }
                    previewImage = image
                    editorText = ""
                    isEditorDirty = false
                    editingFileURL = url
                    loadingFileURL = nil
                    isEditorLoading = false
                }
            }
        } else {
            // Text file — cap at 1MB
            if fileSize > 1_000_000 {
                editingFileURL = nil
                loadingFileURL = nil
                previewImage = nil
                return
            }
            Task.detached(priority: .userInitiated) {
                let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                await MainActor.run {
                    guard loadingFileURL == url else { return }
                    previewImage = nil
                    editorText = content
                    editorState = SourceEditorState()
                    isEditorDirty = false
                    editingFileURL = url
                    loadingFileURL = nil
                }
                try? await Task.sleep(for: .milliseconds(50))
                await MainActor.run {
                    guard editingFileURL == url else { return }
                    isEditorLoading = false
                }
            }
        }
    }

    private func saveCurrentFile() {
        guard let url = editingFileURL, isEditorDirty else { return }
        do {
            try editorText.write(to: url, atomically: true, encoding: .utf8)
            isEditorDirty = false
            store.refreshNow()
        } catch {
            store.errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }

    private var editorLanguage: CodeLanguage {
        guard let url = store.selectedNode?.url else {
            return .default
        }
        return CodeLanguage.detectLanguageFrom(url: url)
    }

    private func stageFile(_ node: FileExplorerNode) {
        guard node.gitState != nil else { return }
        gitStore.stage(paths: [store.relativePath(for: node)])
    }

    private func discardFile(_ node: FileExplorerNode) {
        guard node.gitState != nil else { return }
        gitStore.discardByPath(store.relativePath(for: node))
    }

    private func openDiff(_ node: FileExplorerNode) {
        guard !node.isDirectory else { return }
        navigationStore.activeTab = .gitChanges
        gitStore.openDiff(forFileURL: node.url)
    }

    // MARK: - Editor Panel

    private var editorPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                if let node = store.selectedNode {
                    Image(systemName: fileIcon(for: node))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(node.name)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)

                    if isEditorDirty {
                        Circle()
                            .fill(Color.primary)
                            .frame(width: 5, height: 5)
                    }
                }
                Spacer()

                if isEditorDirty {
                    Text("Modified")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: AppConstants.headerHeight)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            if editingFileURL != nil, isImageFile, let image = previewImage {
                // Image preview
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
            } else if editingFileURL != nil, !isImageFile {
                SourceEditor(
                    $editorText,
                    language: editorLanguage,
                    configuration: editorConfiguration,
                    state: $editorState
                )
                .id(editingFileURL)
                .onChange(of: editorText) { _, _ in
                    if editingFileURL != nil, !isEditorLoading {
                        isEditorDirty = true
                    }
                }
            } else {
                Spacer()
                Text("Select a file to edit")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
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
}
