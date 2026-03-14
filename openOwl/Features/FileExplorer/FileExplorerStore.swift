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

    var selectedNode: FileExplorerNode? {
        guard let selectedNodeID else { return nil }
        return nodeIndex[selectedNodeID]
    }

    var quickOpenMatches: [FileQuickOpenMatch] {
        guard !searchableFileNodes.isEmpty else { return [] }

        let query = quickOpenQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !query.isEmpty else {
            return searchableFileNodes
                .prefix(200)
                .map { FileQuickOpenMatch(node: $0, score: 0) }
        }

        return searchableFileNodes
            .compactMap { node in
                guard let score = Self.quickOpenScore(for: node, query: query) else { return nil }
                return FileQuickOpenMatch(node: node, score: score)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                return lhs.node.url.path.localizedStandardCompare(rhs.node.url.path) == .orderedAscending
            }
            .prefix(200)
            .map { $0 }
    }

    func setProject(_ url: URL?) {
        let standardized = url?.standardizedFileURL
        guard projectURL != standardized else { return }

        projectURL = standardized
        selectedNodeID = nil
        previewState = .none
        errorMessage = nil
        dismissQuickOpen()

        configureWatcher()
        refreshNow()
    }

    func refreshNow() {
        Task {
            await refresh()
        }
    }

    func selectNode(_ nodeID: String?) {
        selectedNodeID = nodeID
        loadPreviewForSelection()
    }

    func presentQuickOpen() {
        guard !searchableFileNodes.isEmpty else { return }
        quickOpenQuery = ""
        isQuickOpenPresented = true
        syncQuickOpenSelection()
    }

    func dismissQuickOpen() {
        isQuickOpenPresented = false
        quickOpenQuery = ""
        quickOpenSelectionID = nil
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

        let gitContext = await loadGitContext(for: projectURL)
        let capturedURL = projectURL
        let result = await Task.detached(priority: .userInitiated) {
            Self.scanProject(projectURL: capturedURL, gitContext: gitContext)
        }.value

        rootNodes = result.nodes
        nodeIndex = result.index
        searchableFileNodes = result.index.values
            .filter { !$0.isDirectory }
            .sorted { lhs, rhs in
                lhs.url.path.localizedStandardCompare(rhs.url.path) == .orderedAscending
            }

        if let selectedNodeID, nodeIndex[selectedNodeID] == nil {
            self.selectedNodeID = nil
        }
        syncQuickOpenSelection()

        loadPreviewForSelection()
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

    private func loadGitContext(for projectURL: URL) async -> GitContext {
        let probe = GitService(workingDirectory: projectURL)
        guard let repositoryRoot = try? await probe.repositoryRoot() else {
            return GitContext.empty
        }

        let gitService = GitService(workingDirectory: repositoryRoot)
        var statusByAbsolutePath: [String: FileGitState] = [:]

        if let snapshot = try? await gitService.status() {
            let allChanges = snapshot.staged + snapshot.modified + snapshot.untracked
            for change in allChanges {
                let absolutePath = repositoryRoot
                    .appendingPathComponent(change.path)
                    .standardizedFileURL
                    .path

                let state = Self.classifyGitState(for: change)
                let existing = statusByAbsolutePath[absolutePath]
                statusByAbsolutePath[absolutePath] = Self.mergeGitState(existing, state)
            }
        }

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
            statusByAbsolutePath: statusByAbsolutePath,
            ignoredExactPaths: compactedExactPaths,
            ignoredDirectoryPrefixes: compactedPrefixes
        )
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

    nonisolated static func quickOpenScore(for node: FileExplorerNode, query: String) -> Int? {
        let name = node.name.lowercased()
        let path = node.url.path.lowercased()

        guard path.contains(query) else { return nil }

        var score = 0

        if name == query {
            score += 1200
        }
        if name.hasPrefix(query) {
            score += 700
        }

        if let nameMatchRange = name.range(of: query) {
            let distance = name.distance(from: name.startIndex, to: nameMatchRange.lowerBound)
            score += max(420 - distance * 12, 80)
        }

        if let pathMatchRange = path.range(of: query) {
            let distance = path.distance(from: path.startIndex, to: pathMatchRange.lowerBound)
            score += max(240 - distance, 30)
        }

        let pathDepth = path.split(separator: "/").count
        score += max(90 - pathDepth * 2, 0)

        if node.gitState != nil {
            score += 16
        }

        return score
    }

    nonisolated static func scanProject(projectURL: URL, gitContext: GitContext) -> ScanResult {
        var index: [String: FileExplorerNode] = [:]
        let topLevelURLs = directoryEntries(at: projectURL)
        let sortedURLs = sortEntries(topLevelURLs)

        let nodes = sortedURLs.compactMap { url in
            buildNode(url: url, gitContext: gitContext, index: &index)
        }

        return ScanResult(nodes: nodes, index: index)
    }

    nonisolated static func buildNode(
        url: URL,
        gitContext: GitContext,
        index: inout [String: FileExplorerNode]
    ) -> FileExplorerNode? {
        if shouldIgnore(url: url, gitContext: gitContext) {
            return nil
        }

        let path = url.standardizedFileURL.path
        let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        let isDirectory = resourceValues?.isDirectory ?? false
        let isSymbolicLink = resourceValues?.isSymbolicLink ?? false

        if isDirectory && !isSymbolicLink {
            let childURLs = sortEntries(directoryEntries(at: url))
            var children: [FileExplorerNode] = []
            children.reserveCapacity(childURLs.count)

            for childURL in childURLs {
                if let childNode = buildNode(url: childURL, gitContext: gitContext, index: &index) {
                    children.append(childNode)
                }
            }

            var state = gitContext.statusByAbsolutePath[path]
            for child in children {
                state = mergeGitState(state, child.gitState)
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

    nonisolated static func shouldIgnore(url: URL, gitContext: GitContext) -> Bool {
        let path = url.standardizedFileURL.path

        if url.lastPathComponent == ".git" {
            return true
        }
        if url.lastPathComponent == ".DS_Store" {
            return true
        }

        if gitContext.ignoredExactPaths.contains(path) {
            return true
        }

        for prefix in gitContext.ignoredDirectoryPrefixes {
            if path == prefix || path.hasPrefix(prefix + "/") {
                return true
            }
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
