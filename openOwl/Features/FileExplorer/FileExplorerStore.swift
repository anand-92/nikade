import AppKit
import Combine
import Foundation

enum FileGitState: String, Hashable {
    case added
    case modified
    case deleted
    case renamed
    case conflicted

    var priority: Int {
        switch self {
        case .conflicted:
            return 5
        case .deleted:
            return 4
        case .renamed:
            return 3
        case .modified:
            return 2
        case .added:
            return 1
        }
    }

    var shortCode: String {
        switch self {
        case .added:
            return "A"
        case .modified:
            return "M"
        case .deleted:
            return "D"
        case .renamed:
            return "R"
        case .conflicted:
            return "U"
        }
    }
}

struct FileExplorerNode: Identifiable, Hashable {
    let id: String
    let url: URL
    let name: String
    let isDirectory: Bool
    let gitState: FileGitState?
    let children: [FileExplorerNode]?
    // For directories: children == nil means "not yet scanned" (lazy)
    // children == [] means "scanned and empty"
    // For files: children is always nil
}

enum FilePreviewState {
    case none
    case directory(path: String, itemCount: Int)
    case text(content: String, truncated: Bool)
    case binary
    case unavailable(message: String)
}

struct FileQuickOpenMatch: Identifiable, Hashable {
    let node: FileExplorerNode
    let score: Int
    let matchedIndices: [Int] // character indices in node.name that matched the query

    var id: String { node.id }
}

@MainActor
final class FileExplorerStore: ObservableObject {
    @Published private(set) var projectURL: URL?
    @Published private(set) var rootNodes: [FileExplorerNode] = []
    @Published private(set) var isRefreshing = false
    @Published var selectedNodeID: String?
    @Published private(set) var previewState: FilePreviewState = .none
    @Published var errorMessage: String?
    @Published var isQuickOpenPresented = false
    @Published var quickOpenQuery: String = ""
    @Published var quickOpenSelectionID: String?

    private(set) var nodeIndex: [String: FileExplorerNode] = [:]
    private var searchableFileNodes: [FileExplorerNode] = []
    private var watcher: FileWatcher?
    private var querySubscription: AnyCancellable?

    func setupQueryAutoSearch() {
        guard querySubscription == nil else { return }
        querySubscription = $quickOpenQuery
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateQuickOpenResults()
            }
    }

    // Cache scan results per project to avoid re-scanning on switch
    private struct ProjectCache {
        let nodes: [FileExplorerNode]
        let index: [String: FileExplorerNode]
    }
    private var projectScanCache: [String: ProjectCache] = [:]

    var selectedNode: FileExplorerNode? {
        guard let selectedNodeID else { return nil }
        return nodeIndex[selectedNodeID]
    }

    @Published private(set) var quickOpenResults: [FileQuickOpenMatch] = []
    private var quickOpenWorkItem: DispatchWorkItem?
    private var quickOpenGeneration: Int = 0

    var quickOpenMatches: [FileQuickOpenMatch] { quickOpenResults }

    func updateQuickOpenResults() {
        quickOpenWorkItem?.cancel()
        quickOpenWorkItem = nil

        let query = quickOpenQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let nodes = searchableFileNodes

        guard !nodes.isEmpty else {
            quickOpenResults = []
            return
        }

        guard !query.isEmpty else {
            quickOpenResults = Array(nodes.prefix(200).map { FileQuickOpenMatch(node: $0, score: 0, matchedIndices: []) })
            return
        }

        // Synchronous fuzzy search — fast enough for <20k nodes
        let results: [FileQuickOpenMatch] = nodes
            .compactMap { node -> FileQuickOpenMatch? in
                guard let result = FileExplorerStore.quickOpenScore(for: node, query: query) else { return nil }
                return FileQuickOpenMatch(node: node, score: result.score, matchedIndices: result.indices)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.node.url.path.localizedStandardCompare(rhs.node.url.path) == .orderedAscending
            }
        quickOpenResults = Array(results.prefix(50))
    }

    func setProject(_ url: URL?) {
        let standardized = url?.standardizedFileURL
        guard projectURL != standardized else { return }

        // Save current project's state to cache
        if let oldURL = projectURL, !rootNodes.isEmpty {
            projectScanCache[oldURL.path] = ProjectCache(nodes: rootNodes, index: nodeIndex)
        }

        projectURL = standardized
        selectedNodeID = nil
        previewState = .none
        errorMessage = nil
        dismissQuickOpen()

        // Restore from cache if available (instant)
        if let standardized, let cached = projectScanCache[standardized.path] {
            rootNodes = cached.nodes
            nodeIndex = cached.index
            searchableFileNodes = cached.index.values
                .filter { !$0.isDirectory }
                .sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
        } else {
            rootNodes = []
            nodeIndex = [:]
        }

        configureWatcher()
        refreshNow()
    }

    func refreshNow() {
        Task {
            await refresh()
        }
    }

    /// Lazily scan a directory's children when user expands it
    func expandDirectory(_ dirPath: String) {
        guard let node = nodeIndex[dirPath], node.isDirectory, node.children == nil else { return }

        // Scan this directory synchronously (single directory is fast)
        let childURLs = Self.sortEntries(Self.directoryEntries(at: node.url))
        var newChildren: [FileExplorerNode] = []
        for url in childURLs {
            if Self.shouldIgnore(url: url, gitContext: .empty) { continue }
            let path = url.standardizedFileURL.path
            let rv = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            let isDir = rv?.isDirectory ?? false
            let isSym = rv?.isSymbolicLink ?? false
            let child = FileExplorerNode(
                id: path, url: url,
                name: Self.displayName(for: url),
                isDirectory: isDir && !isSym,
                gitState: nil,
                children: (isDir && !isSym) ? nil : nil // lazy for subdirs too
            )
            nodeIndex[child.id] = child
            newChildren.append(child)
        }

        // Update the parent node with children
        let updated = FileExplorerNode(
            id: node.id, url: node.url, name: node.name,
            isDirectory: true, gitState: node.gitState,
            children: newChildren
        )
        nodeIndex[updated.id] = updated

        // Update in rootNodes tree
        rootNodes = Self.replaceNode(in: rootNodes, id: dirPath, with: updated)

        // Add new files to searchable list
        let newFiles = newChildren.filter { !$0.isDirectory }
        if !newFiles.isEmpty {
            searchableFileNodes.append(contentsOf: newFiles)
        }
    }

    private static func replaceNode(in nodes: [FileExplorerNode], id: String, with replacement: FileExplorerNode) -> [FileExplorerNode] {
        nodes.map { node in
            if node.id == id { return replacement }
            if let children = node.children {
                let updated = replaceNode(in: children, id: id, with: replacement)
                if updated != children {
                    return FileExplorerNode(id: node.id, url: node.url, name: node.name,
                                           isDirectory: node.isDirectory, gitState: node.gitState, children: updated)
                }
            }
            return node
        }
    }

    func selectNode(_ nodeID: String?) {
        selectedNodeID = nodeID
        loadPreviewForSelection()
    }

    func presentQuickOpen() {
        guard !searchableFileNodes.isEmpty else { return }
        quickOpenGeneration += 1  // Invalidate any pending dismiss async block
        quickOpenQuery = ""
        isQuickOpenPresented = true
        syncQuickOpenSelection()
    }

    func dismissQuickOpen() {
        quickOpenWorkItem?.cancel()
        quickOpenGeneration += 1
        let gen = quickOpenGeneration
        // Defer to avoid "Publishing changes from within view updates"
        // when called from .onChange or other view-update contexts.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.quickOpenGeneration == gen else { return }
            self.isQuickOpenPresented = false
            self.quickOpenQuery = ""
            self.quickOpenResults = []
            self.quickOpenSelectionID = nil
        }
    }

    func selectQuickOpenResult(_ resultID: String?) {
        quickOpenSelectionID = resultID
    }

    func syncQuickOpenSelection() {
        let matches = quickOpenMatches
        guard !matches.isEmpty else {
            quickOpenSelectionID = nil
            return
        }

        if let quickOpenSelectionID,
           matches.contains(where: { $0.id == quickOpenSelectionID }) {
            return
        }

        quickOpenSelectionID = matches[0].id
    }

    func openQuickOpenSelection() -> FileExplorerNode? {
        let targetID = quickOpenSelectionID ?? quickOpenMatches.first?.id
        guard let targetID,
              let node = nodeIndex[targetID] else { return nil }

        selectNode(targetID)
        dismissQuickOpen()
        return node
    }

    func isChangedFile(_ node: FileExplorerNode) -> Bool {
        !node.isDirectory && node.gitState != nil
    }

    func relativePath(for node: FileExplorerNode) -> String {
        guard let projectURL else { return node.url.path }
        let rootPath = projectURL.standardizedFileURL.path
        let filePath = node.url.standardizedFileURL.path

        if filePath == rootPath {
            return "."
        }
        if filePath.hasPrefix(rootPath + "/") {
            return String(filePath.dropFirst(rootPath.count + 1))
        }

        return filePath
    }

    func copyPath(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.path, forType: .string)
    }

    // MARK: - File Operations

    /// Copy file URLs to pasteboard (for Cmd+C)
    func copyFiles(_ urls: [URL]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
    }

    /// Cut files: copy to pasteboard and mark for move
    func cutFiles(_ urls: [URL]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
        // Store cut state — on paste we move instead of copy
        UserDefaults.standard.set(true, forKey: "openowl.fileCutPending")
    }

    /// Paste files from pasteboard into target directory
    func pasteFiles(into targetDirectory: URL) {
        let pasteboard = NSPasteboard.general
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else { return }

        let isCut = UserDefaults.standard.bool(forKey: "openowl.fileCutPending")
        UserDefaults.standard.removeObject(forKey: "openowl.fileCutPending")

        let fm = FileManager.default
        for url in urls {
            let destURL = targetDirectory.appendingPathComponent(url.lastPathComponent)
            do {
                if isCut {
                    try fm.moveItem(at: url, to: destURL)
                } else {
                    try fm.copyItem(at: url, to: destURL)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        refreshNow()
    }

    /// Rename file/folder
    func renameNode(_ node: FileExplorerNode, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != node.name else { return }

        let newURL = node.url.deletingLastPathComponent().appendingPathComponent(trimmed)
        do {
            try FileManager.default.moveItem(at: node.url, to: newURL)
            refreshNow()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Delete files (move to Trash)
    func deleteNodes(_ urls: [URL]) {
        let pathsToRemove = Set(urls.map { $0.standardizedFileURL.path })

        // Immediately remove from UI
        func filterNodes(_ nodes: [FileExplorerNode]) -> [FileExplorerNode] {
            nodes.compactMap { node in
                if pathsToRemove.contains(node.url.standardizedFileURL.path) { return nil }
                if let children = node.children {
                    let filtered = filterNodes(children)
                    return FileExplorerNode(id: node.id, url: node.url, name: node.name,
                                            isDirectory: node.isDirectory, gitState: node.gitState,
                                            children: filtered)
                }
                return node
            }
        }
        rootNodes = filterNodes(rootNodes)

        for id in pathsToRemove {
            nodeIndex.removeValue(forKey: id)
            if selectedNodeID == id { selectedNodeID = nil; previewState = .none }
        }

        // Trash in background
        DispatchQueue.global(qos: .userInitiated).async {
            for url in urls {
                try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
            }
        }
    }

    func openInTerminal(_ node: FileExplorerNode) {
        let target = node.isDirectory ? node.url : node.url.deletingLastPathComponent()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", target.path]

        do {
            try process.run()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refresh() async {
        guard !isRefreshing else { return }
        guard let projectURL else {
            rootNodes = []
            nodeIndex = [:]
            previewState = .none
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        let capturedURL = projectURL
        let t0 = CFAbsoluteTimeGetCurrent()

        // Phase 1: Scan root level only (instant, ~1ms)
        let shallowResult = await Task.detached(priority: .userInitiated) {
            Self.scanProject(projectURL: capturedURL, gitContext: .empty, maxDepth: 1)
        }.value
        NSLog("FileExplorer: shallow scan %.0fms (%d nodes)", (CFAbsoluteTimeGetCurrent() - t0) * 1000, shallowResult.index.count)

        rootNodes = shallowResult.nodes
        nodeIndex = shallowResult.index
        searchableFileNodes = shallowResult.index.values
            .filter { !$0.isDirectory }
            .sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }

        // Phase 2: Full scan with gitignore + git status
        let t1 = CFAbsoluteTimeGetCurrent()
        async let ignoreCtx = loadIgnoreContext(for: capturedURL)
        async let statusMap = loadGitStatus(for: capturedURL)
        let (ignore, status) = await (ignoreCtx, statusMap)
        guard projectURL == capturedURL else { return }

        let gitContext = GitContext(
            statusByAbsolutePath: status,
            ignoredExactPaths: ignore.ignoredExactPaths,
            ignoredDirectoryPrefixes: ignore.ignoredDirectoryPrefixes
        )
        let (fullResult, sortedFiles) = await Task.detached(priority: .userInitiated) {
            let result = Self.scanProject(projectURL: capturedURL, gitContext: gitContext)
            let files = result.index.values
                .filter { !$0.isDirectory }
                .sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
            return (result, files)
        }.value
        guard projectURL == capturedURL else { return }
        NSLog("FileExplorer: full scan %.0fms (%d nodes)", (CFAbsoluteTimeGetCurrent() - t1) * 1000, fullResult.index.count)

        rootNodes = fullResult.nodes
        nodeIndex = fullResult.index
        searchableFileNodes = sortedFiles

        if let selectedNodeID, nodeIndex[selectedNodeID] == nil {
            self.selectedNodeID = nil
        }
        syncQuickOpenSelection()
        loadPreviewForSelection()

        // Update cache
        projectScanCache[capturedURL.path] = ProjectCache(nodes: rootNodes, index: nodeIndex)
    }

    private func configureWatcher() {
        watcher?.stop()
        watcher = nil

        guard let projectURL else { return }

        watcher = FileWatcher(directoryURL: projectURL) { [weak self] in
            self?.refreshNow()
        }
        watcher?.start()
    }

    private func loadPreviewForSelection() {
        guard let node = selectedNode else {
            previewState = .none
            return
        }

        if node.isDirectory {
            previewState = .directory(
                path: node.url.path,
                itemCount: node.children?.count ?? 0
            )
            return
        }

        previewState = Self.makePreviewState(for: node.url)
    }

    private var cachedRepoRoot: [String: URL] = [:]

    private func repoRoot(for projectURL: URL) async -> URL? {
        let key = projectURL.path
        if let cached = cachedRepoRoot[key] { return cached }
        let probe = GitService(workingDirectory: projectURL)
        guard let root = try? await probe.repositoryRoot() else { return nil }
        cachedRepoRoot[key] = root
        return root
    }

    /// Fast: only gitignore list, no status
    private func loadIgnoreContext(for projectURL: URL) async -> GitContext {
        guard let repositoryRoot = await repoRoot(for: projectURL) else { return .empty }
        let gitService = GitService(workingDirectory: repositoryRoot)

        var ignoredExactPaths: Set<String> = []
        var ignoredDirectoryPrefixes: [String] = []

        if let ignoredPaths = try? await gitService.ignoredPaths() {
            for ignoredPath in ignoredPaths {
                let normalized = ignoredPath.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else { continue }

                if normalized.hasSuffix("/") {
                    let directoryPath = String(normalized.dropLast())
                    let absolutePath = repositoryRoot
                        .appendingPathComponent(directoryPath)
                        .standardizedFileURL
                        .path
                    ignoredDirectoryPrefixes.append(absolutePath)
                } else {
                    let absolutePath = repositoryRoot
                        .appendingPathComponent(normalized)
                        .standardizedFileURL
                        .path
                    ignoredExactPaths.insert(absolutePath)
                }
            }
        }

        let compactedPrefixes = Self.compactDirectoryPrefixes(ignoredDirectoryPrefixes)
        let compactedExactPaths = Set(ignoredExactPaths.filter { ignoredPath in
            !compactedPrefixes.contains { prefix in
                ignoredPath == prefix || ignoredPath.hasPrefix(prefix + "/")
            }
        })

        return GitContext(
            statusByAbsolutePath: [:],
            ignoredExactPaths: compactedExactPaths,
            ignoredDirectoryPrefixes: compactedPrefixes
        )
    }

    /// Slower: git status for change markers (A/M/D)
    private func loadGitStatus(for projectURL: URL) async -> [String: FileGitState] {
        guard let repositoryRoot = await repoRoot(for: projectURL) else { return [:] }
        let gitService = GitService(workingDirectory: repositoryRoot)
        var statusMap: [String: FileGitState] = [:]

        if let snapshot = try? await gitService.status() {
            let allChanges = snapshot.staged + snapshot.modified + snapshot.untracked
            for change in allChanges {
                let absolutePath = repositoryRoot
                    .appendingPathComponent(change.path)
                    .standardizedFileURL
                    .path
                let state = Self.classifyGitState(for: change)
                let existing = statusMap[absolutePath]
                statusMap[absolutePath] = Self.mergeGitState(existing, state)
            }
        }
        return statusMap
    }
}

private extension FileExplorerStore {
    struct ScanResult {
        let nodes: [FileExplorerNode]
        let index: [String: FileExplorerNode]
    }

    struct GitContext {
        let statusByAbsolutePath: [String: FileGitState]
        let ignoredExactPaths: Set<String>
        let ignoredDirectoryPrefixes: [String]

        static let empty = GitContext(
            statusByAbsolutePath: [:],
            ignoredExactPaths: [],
            ignoredDirectoryPrefixes: []
        )
    }

    nonisolated static func classifyGitState(for change: GitFileChange) -> FileGitState {
        let index = change.indexStatus
        let workTree = change.workTreeStatus

        if isConflict(indexStatus: index, workTreeStatus: workTree) {
            return .conflicted
        }
        if index == "D" || workTree == "D" {
            return .deleted
        }
        if index == "R" || workTree == "R" || index == "C" || workTree == "C" {
            return .renamed
        }
        if index == "A" || workTree == "A" || index == "?" || workTree == "?" || change.section == .untracked {
            return .added
        }
        if index == "M" || workTree == "M" || index == "T" || workTree == "T" {
            return .modified
        }
        return .modified
    }

    nonisolated static func mergeGitState(_ lhs: FileGitState?, _ rhs: FileGitState?) -> FileGitState? {
        guard let lhs else { return rhs }
        guard let rhs else { return lhs }
        return lhs.priority >= rhs.priority ? lhs : rhs
    }

    nonisolated static func isConflict(indexStatus: Character, workTreeStatus: Character) -> Bool {
        if indexStatus == "U" || workTreeStatus == "U" {
            return true
        }
        if indexStatus == "A" && workTreeStatus == "A" {
            return true
        }
        if indexStatus == "D" && workTreeStatus == "D" {
            return true
        }
        return false
    }

    nonisolated static func compactDirectoryPrefixes(_ prefixes: [String]) -> [String] {
        let sorted = Array(Set(prefixes)).sorted { lhs, rhs in
            if lhs.count != rhs.count {
                return lhs.count < rhs.count
            }
            return lhs < rhs
        }

        var compacted: [String] = []
        compacted.reserveCapacity(sorted.count)

        for prefix in sorted {
            if compacted.contains(where: { prefix == $0 || prefix.hasPrefix($0 + "/") }) {
                continue
            }
            compacted.append(prefix)
        }

        return compacted
    }

    /// Fuzzy match: query characters must appear in order but not contiguously.
    /// Returns (score, matchedIndices in name) or nil if no match.
    nonisolated static func fuzzyMatch(name: String, path: String, query: String) -> (score: Int, indices: [Int])? {
        let nameLower = name.lowercased()
        let pathLower = path.lowercased()
        let nameChars = Array(nameLower)
        let queryChars = Array(query)

        guard !queryChars.isEmpty else { return (0, []) }

        // Try matching against name first
        if let (nameScore, indices) = fuzzyScoreString(nameChars, query: queryChars) {
            var score = nameScore + 500
            if nameLower == query { score += 1000 }
            if nameLower.hasPrefix(query) { score += 600 }
            let depth = pathLower.split(separator: "/").count
            score += max(100 - depth * 3, 0)
            return (score, indices)
        }

        // Fallback: substring match against path (not fuzzy — avoids false positives)
        if pathLower.contains(query) {
            let depth = pathLower.split(separator: "/").count
            let score = 50 + max(100 - depth * 3, 0)
            return (score, [])
        }

        return nil
    }

    /// Score a fuzzy match of query against target characters.
    /// Returns (score, matched indices) or nil.
    private nonisolated static func fuzzyScoreString(_ target: [Character], query: [Character]) -> (Int, [Int])? {
        var queryIdx = 0
        var matchedIndices: [Int] = []
        var score = 0
        var prevMatchIdx = -1

        for (i, ch) in target.enumerated() {
            guard queryIdx < query.count else { break }
            if ch == query[queryIdx] {
                matchedIndices.append(i)
                // Consecutive match bonus
                if prevMatchIdx == i - 1 { score += 8 }
                // Start of word bonus (after separator or camelCase)
                if i == 0 || target[i - 1] == "/" || target[i - 1] == "." || target[i - 1] == "-" || target[i - 1] == "_"
                    || (target[i - 1].isLowercase && ch.isUppercase) {
                    score += 12
                }
                // Early match bonus
                score += max(10 - i, 0)
                score += 4 // base per-character match
                prevMatchIdx = i
                queryIdx += 1
            }
        }

        guard queryIdx == query.count else { return nil } // not all query chars matched
        return (score, matchedIndices)
    }

    nonisolated static func quickOpenScore(for node: FileExplorerNode, query: String) -> (score: Int, indices: [Int])? {
        fuzzyMatch(name: node.name, path: node.url.path.lowercased(), query: query)
    }

    nonisolated static func scanProject(projectURL: URL, gitContext: GitContext, maxDepth: Int = .max) -> ScanResult {
        var index: [String: FileExplorerNode] = [:]
        let topLevelURLs = directoryEntries(at: projectURL)
        let sortedURLs = sortEntries(topLevelURLs)

        let nodes = sortedURLs.compactMap { url in
            buildNode(url: url, gitContext: gitContext, index: &index, depth: 0, maxDepth: maxDepth)
        }

        return ScanResult(nodes: nodes, index: index)
    }

    nonisolated static func buildNode(
        url: URL,
        gitContext: GitContext,
        index: inout [String: FileExplorerNode],
        depth: Int = 0,
        maxDepth: Int = .max
    ) -> FileExplorerNode? {
        if shouldIgnore(url: url, gitContext: gitContext) {
            return nil
        }

        let path = url.standardizedFileURL.path
        let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        let isDirectory = resourceValues?.isDirectory ?? false
        let isSymbolicLink = resourceValues?.isSymbolicLink ?? false

        if isDirectory && !isSymbolicLink {
            // Don't recurse into gitignored directories (node_modules etc.)
            // Show the directory itself with children=nil (lazy, scan on expand)
            let isGitIgnored = Self.isGitIgnored(path: path, gitContext: gitContext)
            let children: [FileExplorerNode]?
            if depth >= maxDepth || isGitIgnored {
                children = nil // lazy: will scan when user expands
            } else {
                let childURLs = sortEntries(directoryEntries(at: url))
                var built: [FileExplorerNode] = []
                built.reserveCapacity(childURLs.count)
                for childURL in childURLs {
                    if let childNode = buildNode(url: childURL, gitContext: gitContext, index: &index, depth: depth + 1, maxDepth: maxDepth) {
                        built.append(childNode)
                    }
                }
                children = built
            }

            var state = gitContext.statusByAbsolutePath[path]
            if let children {
                for child in children {
                    state = mergeGitState(state, child.gitState)
                }
            }

            let node = FileExplorerNode(
                id: path,
                url: url,
                name: displayName(for: url),
                isDirectory: true,
                gitState: state,
                children: children
            )
            index[node.id] = node
            return node
        }

        let node = FileExplorerNode(
            id: path,
            url: url,
            name: displayName(for: url),
            isDirectory: false,
            gitState: gitContext.statusByAbsolutePath[path],
            children: nil
        )
        index[node.id] = node
        return node
    }

    private static let alwaysIgnoredNames: Set<String> = [
        ".git", ".DS_Store", ".build", "DerivedData",
        "ghostty-resources", "GhosttyKit.xcframework"
    ]

    nonisolated static func shouldIgnore(url: URL, gitContext: GitContext) -> Bool {
        alwaysIgnoredNames.contains(url.lastPathComponent)
    }

    nonisolated static func isGitIgnored(path: String, gitContext: GitContext) -> Bool {
        if gitContext.ignoredExactPaths.contains(path) { return true }
        for prefix in gitContext.ignoredDirectoryPrefixes {
            if path == prefix || path.hasPrefix(prefix + "/") { return true }
        }
        return false
    }

    nonisolated static func directoryEntries(at directoryURL: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants]
        )) ?? []
    }

    nonisolated static func sortEntries(_ entries: [URL]) -> [URL] {
        entries.sorted { lhs, rhs in
            let lhsValues = try? lhs.resourceValues(forKeys: [.isDirectoryKey])
            let rhsValues = try? rhs.resourceValues(forKeys: [.isDirectoryKey])
            let lhsIsDirectory = lhsValues?.isDirectory ?? false
            let rhsIsDirectory = rhsValues?.isDirectory ?? false

            if lhsIsDirectory != rhsIsDirectory {
                return lhsIsDirectory
            }

            return displayName(for: lhs)
                .localizedStandardCompare(displayName(for: rhs)) == .orderedAscending
        }
    }

    nonisolated static func displayName(for url: URL) -> String {
        let name = url.lastPathComponent
        return name.isEmpty ? url.path : name
    }

    static func makePreviewState(for fileURL: URL) -> FilePreviewState {
        let maxPreviewBytes = 160_000

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
            let data = try readPrefixData(from: fileURL, maxBytes: maxPreviewBytes)

            if data.firstIndex(of: 0) != nil {
                return .binary
            }

            let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)

            guard let text else {
                return .binary
            }

            let truncated = fileSize > data.count
            return .text(content: text, truncated: truncated)
        } catch {
            return .unavailable(message: error.localizedDescription)
        }
    }

    static func readPrefixData(from fileURL: URL, maxBytes: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        return try handle.read(upToCount: maxBytes) ?? Data()
    }
}
