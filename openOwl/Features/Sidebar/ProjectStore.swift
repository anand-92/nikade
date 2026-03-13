import AppKit
import Combine
import Foundation

struct ProjectItem: Identifiable, Hashable {
    let id: String
    let url: URL

    init(url: URL) {
        let normalized = url.standardizedFileURL
        self.id = normalized.path
        self.url = normalized
    }

    var displayName: String {
        url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }
}

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [ProjectItem] = []
    @Published var activeProjectID: String?

    private let defaults = UserDefaults.standard
    private let projectsKey = "openowl.projects.paths"
    private let activeProjectKey = "openowl.projects.active"

    init() {
        load()
        seedDefaultProjectIfNeeded()
    }

    var activeProjectURL: URL? {
        guard let activeProjectID else { return nil }
        return projects.first(where: { $0.id == activeProjectID })?.url
    }

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
        let item = ProjectItem(url: url)
        if !projects.contains(item) {
            projects.append(item)
            projects.sort { lhs, rhs in
                lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
        }

        activeProjectID = item.id
        persist()
    }

    func activateProject(id: String) {
        guard projects.contains(where: { $0.id == id }) else { return }
        activeProjectID = id
        persist()
    }

    func removeProject(id: String) {
        projects.removeAll { $0.id == id }

        if activeProjectID == id {
            activeProjectID = projects.first?.id
        }

        persist()
    }

    private func load() {
        let paths = defaults.stringArray(forKey: projectsKey) ?? []
        projects = paths
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            .map(ProjectItem.init(url:))
            .uniqued()

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
        addOrActivateProject(cwdURL)
    }

    private func persist() {
        defaults.set(projects.map { $0.url.path }, forKey: projectsKey)
        defaults.set(activeProjectID, forKey: activeProjectKey)
    }
}

private extension Array where Element == ProjectItem {
    func uniqued() -> [ProjectItem] {
        var seen: Set<ProjectItem> = []
        return filter { seen.insert($0).inserted }
    }
}
