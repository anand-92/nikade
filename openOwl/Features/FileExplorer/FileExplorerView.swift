import AppKit
import SwiftUI
import CodeEditSourceEditor
import CodeEditLanguages

let editorConfiguration = SourceEditorConfiguration(
    appearance: .init(
        theme: EditorTheme(
            text: .init(color: AppPalette.ns.textPrimary),
            insertionPoint: AppPalette.ns.accent,
            invisibles: .init(color: NSColor(white: 0.5, alpha: 0.3)),
            background: AppPalette.ns.surface,
            lineHighlight: AppPalette.ns.elevated,
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

// MARK: - Editor Tab

private struct EditorTab: Identifiable, Equatable {
    let url: URL
    var id: URL { url }
    var name: String { url.lastPathComponent }
}

// MARK: - Dirty Tracking Coordinator

/// Detects text changes in SourceEditor and marks the active tab as dirty.
private class EditTracker: TextViewCoordinator {
    var onTextChanged: (() -> Void)?

    func prepareCoordinator(controller: TextViewController) {
        // Remove minimap and floating views that intercept clicks on the right side.
        // Iterate a snapshot to avoid mutating subviews during enumeration.
        if let scrollView = controller.view.subviews.first as? NSScrollView {
            for subview in Array(scrollView.subviews) {
                let name = type(of: subview).description()
                if name.contains("Minimap") || name.contains("Reformat") {
                    subview.removeFromSuperview()
                }
            }
        }
    }

    func textViewDidChangeText(controller: TextViewController) {
        onTextChanged?()
    }

    func textViewDidChangeSelection(controller: TextViewController, newPositions: [CursorPosition]) {}

    func destroy() {}
}

// MARK: - FileExplorerView

struct FileExplorerView: View {
    @Environment(FileExplorerStore.self) private var store
    @Environment(ProjectStore.self) private var projectStore
    @Environment(GitChangesStore.self) private var gitStore
    @Environment(AppNavigationStore.self) private var navigationStore

    // Tab management
    @State private var openTabs: [EditorTab] = []
    @State private var activeTabURL: URL?
    @State private var tabStorages: [URL: NSTextStorage] = [:]
    @State private var tabImageCache: [URL: NSImage] = [:]
    @State private var dirtyTabs: Set<URL> = []

    // Editor state
    @State private var editorState = SourceEditorState()
    @State private var previewImage: NSImage?
    @State private var isEditorLoading = false
    @State private var loadingFileURL: URL?

    // Dirty tracking coordinator (shared across tab switches)
    @State private var editTracker = EditTracker()

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "webp", "heic", "heif", "ico", "svg", "icns"
    ]

    private var isActiveTabImage: Bool {
        guard let ext = activeTabURL?.pathExtension.lowercased() else { return false }
        return Self.imageExtensions.contains(ext)
    }

    @State private var treePanelWidth: CGFloat = 240

    var body: some View {
        HStack(spacing: 0) {
            treePanel
                .frame(width: treePanelWidth)

            treePanelDivider

            editorPanel
        }
        .onAppear {
            store.setProject(projectStore.activeProjectURL)
            setupEditTracker()
        }
        .onChange(of: projectStore.activeProjectID) { _, _ in
            saveAllDirtyTabs()
            store.setProject(projectStore.activeProjectURL)
            openTabs = []
            activeTabURL = nil
            tabStorages.removeAll()
            tabImageCache.removeAll()
            dirtyTabs.removeAll()
            previewImage = nil
        }
        .onChange(of: store.selectedNodeID) { _, newID in
            // Auto-open file when selected externally (e.g. QuickOpen)
            guard let newID,
                  let node = store.nodeIndex[newID],
                  !node.isDirectory else { return }
            openFileInTab(node)
        }
        .onDisappear {
            saveAllDirtyTabs()
        }
        .background {
            Button("") { saveCurrentTab() }
                .keyboardShortcut("s", modifiers: [.command])
                .hidden()
        }
        .background {
            if !openTabs.isEmpty {
                Button("") { closeActiveTab() }
                    .keyboardShortcut("w", modifiers: [.command])
                    .hidden()
            }
        }
    }

    private func setupEditTracker() {
        editTracker.onTextChanged = { [editTracker] in
            // editTracker captured to keep reference alive; only using self's state
            _ = editTracker
            if let url = activeTabURL, !isEditorLoading {
                dirtyTabs.insert(url)
            }
        }
    }

    // MARK: - Tree Panel

    private var treePanel: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                SectionTitle("EXPLORER")

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
            .padding(.horizontal, AppSpacing.panelPadding)
            .frame(height: AppSpacing.headerHeight)

            PanelDivider()

            if let errorMessage = store.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10))
                    Text(errorMessage).font(AppFonts.caption).lineLimit(1)
                    Spacer()
                    Button { store.errorMessage = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 8))
                    }.buttonStyle(.plain)
                }
                .foregroundStyle(.red)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.red.opacity(0.12))
            }

            if store.rootNodes.isEmpty {
                Spacer()
                EmptyStateView("No files", subtitle: "Open a project to browse files")
                Spacer()
            } else {
                OutlineTreeView(
                    onSelectFile: { node in
                        store.selectNode(node.id)
                        openFileInTab(node)
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
                    },
                    onExpandDirectory: { path in store.expandDirectory(path) }
                )
            }
        }
        .background(EffectView(material: .sidebar, blendingMode: .behindWindow))
    }

    // MARK: - Editor Panel

    private var editorPanel: some View {
        VStack(spacing: 0) {
            // Tab bar
            if !openTabs.isEmpty {
                editorTabBar
            }

            PanelDivider()

            // Editor content
            if let url = activeTabURL {
                if isActiveTabImage, let image = previewImage {
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .background(Color(nsColor: .windowBackgroundColor))
                } else if !isActiveTabImage, let storage = tabStorages[url] {
                    SourceEditor(
                        storage,
                        language: editorLanguage(for: url),
                        configuration: editorConfiguration,
                        state: $editorState,
                        coordinators: [editTracker]
                    )
                    .id(url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                Spacer()
                EmptyStateView("Select a file to edit", subtitle: "Click a file in the explorer or use ⌘P")
                    .frame(maxWidth: .infinity)
                Spacer()
            }
        }
    }

    // MARK: - Resizable Divider

    @State private var dragStartWidth: CGFloat?

    private var treePanelDivider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.2))
            .frame(width: 1)
            .overlay {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                if dragStartWidth == nil { dragStartWidth = treePanelWidth }
                                let newWidth = (dragStartWidth ?? 240) + value.translation.width
                                treePanelWidth = min(max(newWidth, 150), 500)
                            }
                            .onEnded { _ in dragStartWidth = nil }
                    )
            }
    }

    // MARK: - Tab Bar

    private var editorTabBar: some View {
        HStack(spacing: 0) {
            ForEach(openTabs) { tab in
                EditorTabButton(
                    tab: tab,
                    isActive: tab.url == activeTabURL,
                    isDirty: dirtyTabs.contains(tab.url),
                    onSelect: { switchToTab(tab.url) },
                    onClose: { closeTab(tab.url) }
                )
            }
            Spacer(minLength: 0)
        }
        .frame(height: AppSpacing.editorTabBarHeight)
        .background(AppPalette.surface)
    }

    // MARK: - Tab Management

    private func openFileInTab(_ node: FileExplorerNode) {
        guard !node.isDirectory else { return }
        let url = node.url

        // Already open — just switch
        if openTabs.contains(where: { $0.url == url }) {
            if activeTabURL != url {
                switchToTab(url)
            }
            return
        }

        // Size check
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        if fileSize > 10_000_000 { return }

        let ext = url.pathExtension.lowercased()
        let isImage = Self.imageExtensions.contains(ext)

        // Add new tab
        openTabs.append(EditorTab(url: url))
        loadingFileURL = url
        isEditorLoading = true

        if isImage {
            Task.detached(priority: .userInitiated) {
                let image = NSImage(contentsOf: url)
                await MainActor.run {
                    guard loadingFileURL == url else { return }
                    tabImageCache[url] = image
                    previewImage = image
                    activeTabURL = url
                    loadingFileURL = nil
                    isEditorLoading = false
                }
            }
        } else {
            if fileSize > 1_000_000 {
                openTabs.removeAll { $0.url == url }
                loadingFileURL = nil
                isEditorLoading = false
                return
            }
            Task.detached(priority: .userInitiated) {
                let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                let storage = NSTextStorage(string: content)
                await MainActor.run {
                    guard loadingFileURL == url else { return }
                    tabStorages[url] = storage
                    previewImage = nil
                    editorState = SourceEditorState()
                    activeTabURL = url
                    loadingFileURL = nil
                }
                try? await Task.sleep(for: .milliseconds(50))
                await MainActor.run {
                    guard activeTabURL == url else { return }
                    isEditorLoading = false
                }
            }
        }
    }

    private func switchToTab(_ url: URL) {
        guard url != activeTabURL else { return }
        guard openTabs.contains(where: { $0.url == url }) else { return }

        isEditorLoading = true
        activeTabURL = url
        editorState = SourceEditorState()

        let ext = url.pathExtension.lowercased()
        let isImage = Self.imageExtensions.contains(ext)

        if isImage {
            previewImage = tabImageCache[url]
            isEditorLoading = false
        } else {
            previewImage = nil
            // Storage already in tabStorages — SourceEditor recreated via .id(url)
            Task {
                try? await Task.sleep(for: .milliseconds(50))
                guard activeTabURL == url else { return }
                isEditorLoading = false
            }
        }

        // Sync tree selection
        store.selectNode(url.standardizedFileURL.path)
    }

    private func closeTab(_ url: URL) {
        // Auto-save dirty tab
        if dirtyTabs.contains(url) {
            if let storage = tabStorages[url] {
                do {
                    try storage.string.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    store.errorMessage = "Failed to save \(url.lastPathComponent): \(error.localizedDescription)"
                }
            }
        }

        guard let index = openTabs.firstIndex(where: { $0.url == url }) else { return }
        let wasActive = url == activeTabURL

        openTabs.remove(at: index)
        tabStorages.removeValue(forKey: url)
        tabImageCache.removeValue(forKey: url)
        dirtyTabs.remove(url)

        if wasActive {
            if openTabs.isEmpty {
                activeTabURL = nil
                previewImage = nil
            } else {
                let newIndex = min(index, openTabs.count - 1)
                let newURL = openTabs[newIndex].url
                isEditorLoading = true
                activeTabURL = newURL
                editorState = SourceEditorState()

                let ext = newURL.pathExtension.lowercased()
                if Self.imageExtensions.contains(ext) {
                    previewImage = tabImageCache[newURL]
                    isEditorLoading = false
                } else {
                    previewImage = nil
                    Task {
                        try? await Task.sleep(for: .milliseconds(50))
                        guard activeTabURL == newURL else { return }
                        isEditorLoading = false
                    }
                }
            }
        }
    }

    private func closeActiveTab() {
        guard let url = activeTabURL else { return }
        closeTab(url)
    }

    // MARK: - Save

    private func saveCurrentTab() {
        guard let url = activeTabURL,
              dirtyTabs.contains(url),
              let storage = tabStorages[url] else { return }
        do {
            try storage.string.write(to: url, atomically: true, encoding: .utf8)
            dirtyTabs.remove(url)
            store.refreshNow()
        } catch {
            store.errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }

    private func saveAllDirtyTabs() {
        for url in dirtyTabs {
            guard let storage = tabStorages[url] else { continue }
            do {
                try storage.string.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSLog("openOwl: Failed to save %@: %@", url.lastPathComponent, error.localizedDescription)
            }
        }
        dirtyTabs.removeAll()
    }

    // MARK: - Git Actions

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
        navigationStore.navigate(to: .gitChanges)
        gitStore.openDiff(forFileURL: node.url)
    }

    // MARK: - Helpers

    private func editorLanguage(for url: URL) -> CodeLanguage {
        CodeLanguage.detectLanguageFrom(url: url)
    }

    fileprivate static func fileIconName(for url: URL) -> String {
        FileIcons.iconName(for: url)
    }

    fileprivate static func fileIconColor(for url: URL) -> Color {
        FileIcons.iconColor(for: url)
    }

    private func fileIcon(for node: FileExplorerNode) -> String {
        if node.isDirectory { return "folder.fill" }
        return Self.fileIconName(for: node.url)
    }
}

// MARK: - Editor Tab Button

private struct EditorTabButton: View {
    let tab: EditorTab
    let isActive: Bool
    let isDirty: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            // Label area — Button for proper AppKit hit testing inside ScrollView
            Button(action: onSelect) {
                HStack(spacing: 4) {
                    Image(systemName: FileExplorerView.fileIconName(for: tab.url))
                        .font(.system(size: 10))
                        .foregroundStyle(FileExplorerView.fileIconColor(for: tab.url))

                    Text(tab.name)
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
                .padding(.leading, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Close button — separate from select
            closeOrDirtyIndicator
                .padding(.trailing, 4)
        }
        .padding(.trailing, 4)
        .frame(height: AppSpacing.editorTabBarHeight)
        .background(isActive ? AppColors.activeBackground : (isHovering ? AppColors.hoverBackground : Color.clear))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .frame(width: 1)
        }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Close") { onClose() }
        }
    }

    @ViewBuilder
    private var closeOrDirtyIndicator: some View {
        if isDirty && !isHovering {
            Circle()
                .fill(Color.primary.opacity(0.6))
                .frame(width: 6, height: 6)
                .frame(width: 16, height: 16)
        } else if isHovering || isActive {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(width: 16, height: 16)
        }
    }
}
