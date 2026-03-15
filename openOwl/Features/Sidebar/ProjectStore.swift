import AppKit
import Combine
import Foundation

struct ProjectItem: Identifiable, Hashable, Codable {
    let id: String
    let path: String
    var name: String
    var worktreeOf: String?       // parent project id
    var worktreeBranch: String?   // worktree branch name
    var lastBranch: String?       // last known branch (persisted for non-active projects)
    var branchPrefix: String?     // GitHub username or custom prefix for worktree branches

    var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
    var displayName: String { name }
    var isWorktree: Bool { worktreeOf != nil }

    init(url: URL, id: String = UUID().uuidString) {
        let normalized = url.standardizedFileURL
        self.id = id
        self.path = normalized.path
        self.name = normalized.lastPathComponent.isEmpty ? normalized.path : normalized.lastPathComponent
    }

    init(path: String, name: String, id: String = UUID().uuidString, worktreeOf: String? = nil, worktreeBranch: String? = nil) {
        let normalized = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        self.id = id
        self.path = normalized.path
        self.name = name
        self.worktreeOf = worktreeOf
        self.worktreeBranch = worktreeBranch
    }
}

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [ProjectItem] = []
    @Published var activeProjectID: String?
    @Published var collapsedProjectIDs: Set<String> = []

    private let defaults = UserDefaults.standard
    private let storeKey = "openowl.projects.store"
    private let activeProjectKey = "openowl.projects.active"

    /// Branch prefix for the active root project (reads from ProjectItem.branchPrefix)
    var branchPrefix: String {
        guard let activeID = activeProjectID,
              let project = projects.first(where: { $0.id == activeID }) else { return "dev" }
        let root = project.isWorktree
            ? projects.first(where: { $0.id == project.worktreeOf }) ?? project
            : project
        return root.branchPrefix ?? "dev"
    }

    // MARK: - Computed

    var rootProjects: [ProjectItem] {
        projects.filter { !$0.isWorktree }
    }

    func worktrees(for projectID: String) -> [ProjectItem] {
        projects.filter { $0.worktreeOf == projectID }
    }

    var activeProjectURL: URL? {
        guard let activeProjectID else { return nil }
        return projects.first(where: { $0.id == activeProjectID })?.url
    }

    func isExpanded(_ projectID: String) -> Bool {
        !collapsedProjectIDs.contains(projectID)
    }

    func toggleExpanded(_ projectID: String) {
        if collapsedProjectIDs.contains(projectID) {
            collapsedProjectIDs.remove(projectID)
        } else {
            collapsedProjectIDs.insert(projectID)
        }
    }

    // MARK: - Init

    init() {
        load()
        seedDefaultProjectIfNeeded()
    }

    // MARK: - Project Management

    func openProjectPicker() {
        let panel = NSOpenPanel()
        panel.title = "Open Project"
        panel.message = "Choose a project folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let selected = panel.url else { return }
        addOrActivateProject(selected)
    }

    func addOrActivateProject(_ url: URL) {
        let normalized = url.standardizedFileURL.path
        if let existing = projects.first(where: { $0.path == normalized }) {
            activeProjectID = existing.id
            persist()
            return
        }

        let item = ProjectItem(url: url)
        projects.append(item)
        projects.sort { lhs, rhs in
            guard !lhs.isWorktree, !rhs.isWorktree else { return false }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
        activeProjectID = item.id
        persist()
    }

    func activateProject(id: String) {
        guard projects.contains(where: { $0.id == id }) else { return }
        DispatchQueue.main.async {
            self.activeProjectID = id
            self.persist()
            self.detectBranchPrefix(for: id)
        }
    }

    private func detectBranchPrefix(for projectID: String) {
        guard let project = projects.first(where: { $0.id == projectID }) else { return }
        // Find root project
        let rootID = project.isWorktree ? (project.worktreeOf ?? projectID) : projectID
        guard let rootIndex = projects.firstIndex(where: { $0.id == rootID }) else { return }

        // Already detected
        if projects[rootIndex].branchPrefix != nil { return }

        let rootURL = projects[rootIndex].url
        Task {
            let git = GitService(workingDirectory: rootURL)
            let username = await git.remoteUsername()
                ?? NSFullUserName().lowercased().replacingOccurrences(of: " ", with: "")

            await MainActor.run {
                guard let idx = self.projects.firstIndex(where: { $0.id == rootID }) else { return }
                self.projects[idx].branchPrefix = username
                self.persist()
            }
        }
    }

    func removeProject(id: String) {
        // Also remove child worktrees
        let childIDs = worktrees(for: id).map(\.id)
        projects.removeAll { $0.id == id || childIDs.contains($0.id) }

        if activeProjectID == id || childIDs.contains(activeProjectID ?? "") {
            activeProjectID = projects.first?.id
        }
        persist()
    }

    // MARK: - Branch Tracking

    func updateProjectBranch(_ id: String, branch: String) {
        guard let index = projects.firstIndex(where: { $0.id == id }),
              projects[index].lastBranch != branch else { return }
        projects[index].lastBranch = branch
        persist()
    }

    // MARK: - Worktree Management

    func addWorktreeProject(parentID: String, path: String, branch: String) -> ProjectItem {
        if let existing = projects.first(where: { $0.path == path }) {
            activeProjectID = existing.id
            persist()
            return existing
        }

        let item = ProjectItem(
            path: path,
            name: branch,
            worktreeOf: parentID,
            worktreeBranch: branch
        )
        projects.append(item)
        activeProjectID = item.id
        persist()
        return item
    }

    func removeWorktreeProject(id: String) {
        projects.removeAll { $0.id == id }
        if activeProjectID == id {
            // Switch to parent or first project
            if let wt = projects.first(where: { $0.id == id }),
               let parent = projects.first(where: { $0.id == wt.worktreeOf }) {
                activeProjectID = parent.id
            } else {
                activeProjectID = projects.first?.id
            }
        }
        persist()
    }

    func renameWorktreeProject(id: String, newBranch: String) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[index].name = newBranch
        projects[index].worktreeBranch = newBranch
        persist()
    }

    // MARK: - Persistence

    private func load() {
        // Try new JSON format first
        if let data = defaults.data(forKey: storeKey),
           let decoded = try? JSONDecoder().decode([ProjectItem].self, from: data) {
            projects = decoded
                .filter { Self.isReasonableProjectPath(URL(fileURLWithPath: $0.path)) }
                .uniqued()
        } else {
            // Migrate from old string array format
            let paths = defaults.stringArray(forKey: "openowl.projects.paths") ?? []
            projects = paths
                .map { URL(fileURLWithPath: $0, isDirectory: true) }
                .filter { Self.isReasonableProjectPath($0) }
                .map { ProjectItem(url: $0) }
                .uniqued()
        }

        let storedActiveProject = defaults.string(forKey: activeProjectKey)
        if let storedActiveProject,
           projects.contains(where: { $0.id == storedActiveProject }) {
            activeProjectID = storedActiveProject
        } else {
            activeProjectID = projects.first?.id
        }
    }

    private func seedDefaultProjectIfNeeded() {
        guard projects.isEmpty else { return }
        let cwdURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        guard Self.isReasonableProjectPath(cwdURL) else { return }
        addOrActivateProject(cwdURL)
    }

    private static func isReasonableProjectPath(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let components = path.split(separator: "/")
        return components.count >= 3
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(projects) {
            defaults.set(data, forKey: storeKey)
        }
        defaults.set(activeProjectID, forKey: activeProjectKey)
    }
}

private extension Array where Element == ProjectItem {
    func uniqued() -> [ProjectItem] {
        var seen: Set<String> = []
        return filter {
            let normalized = URL(fileURLWithPath: $0.path, isDirectory: true).standardizedFileURL.path
            return seen.insert(normalized).inserted
        }
    }
}
