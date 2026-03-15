import SwiftUI

@main
struct openOwlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var ghosttyManager: GhosttyAppManager
    @StateObject private var workspaceStore = TerminalWorkspaceStore()
    @StateObject private var navigationStore = AppNavigationStore()
    @StateObject private var projectStore: ProjectStore
    @StateObject private var gitChangesStore = GitChangesStore()
    @StateObject private var fileExplorerStore = FileExplorerStore()

    init() {
        Self.setupEnvironment()

        // Set cwd to active project BEFORE ghostty starts, so the first shell
        // opens in the project directory instead of ~
        let store = ProjectStore()
        if let url = store.activeProjectURL {
            FileManager.default.changeCurrentDirectoryPath(url.path)
        }
        _projectStore = StateObject(wrappedValue: store)
        _ghosttyManager = StateObject(wrappedValue: GhosttyAppManager())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ghosttyManager)
                .environmentObject(workspaceStore)
                .environmentObject(navigationStore)
                .environmentObject(projectStore)
                .environmentObject(gitChangesStore)
                .environmentObject(fileExplorerStore)
                .onAppear {
                    appDelegate.workspaceStore = workspaceStore
                    appDelegate.ghosttyManager = ghosttyManager
                    appDelegate.navigationStore = navigationStore
                    ghosttyManager.onPaneTitleChanged = { paneID, title in
                        workspaceStore.updateTitle(for: paneID, title: title)
                    }
                    syncActiveProjectContext()
                }
                .onChange(of: projectStore.activeProjectID) { _, _ in
                    syncActiveProjectContext()
                }
                .onReceive(gitChangesStore.$statusSnapshot) { snapshot in
                    // Keep sidebar branch display in sync with git status
                    guard let snapshot,
                          let activeID = projectStore.activeProjectID,
                          let activeURL = projectStore.activeProjectURL,
                          snapshot.repositoryRoot.standardizedFileURL == activeURL.standardizedFileURL
                    else { return }
                    projectStore.updateProjectBranch(activeID, branch: snapshot.branch)
                }
                .frame(
                    minWidth: AppConstants.windowMinWidth,
                    minHeight: AppConstants.windowMinHeight
                )
        }
        .defaultSize(width: 1200, height: 800)
    }

    private static func setupEnvironment() {
        setenv("TERM", AppConstants.termEnv, 1)

        // GHOSTTY_RESOURCES_DIR: ghostty needs this for terminfo, shell-integration, themes.
        // In dev builds, use the symlinked ghostty-resources in the project root.
        // In release builds, bundle resources inside the .app.
        if let resourcesInBundle = Bundle.main.resourcePath {
            for directoryName in ["ghostty", "ghostty-resources"] {
                let ghosttyRes = (resourcesInBundle as NSString).appendingPathComponent(directoryName)
                if FileManager.default.fileExists(atPath: ghosttyRes) {
                    setenv(AppConstants.ghosttyResourcesDirEnv, ghosttyRes, 1)
                    return
                }
            }
        }

        // Dev fallback: project root's ghostty-resources symlink
        let searchRoots = [
            (Bundle.main.bundlePath as NSString).deletingLastPathComponent,
            FileManager.default.currentDirectoryPath
        ]

        for root in searchRoots {
            var dir = root
            for _ in 0..<8 {
                let candidate = (dir as NSString).appendingPathComponent("ghostty-resources")
                if FileManager.default.fileExists(atPath: candidate) {
                    setenv(AppConstants.ghosttyResourcesDirEnv, candidate, 1)
                    return
                }
                let next = (dir as NSString).deletingLastPathComponent
                if next == dir { break }
                dir = next
            }
        }
    }

    @MainActor
    private func syncActiveProjectContext() {
        let t0 = CFAbsoluteTimeGetCurrent()
        guard let projectURL = projectStore.activeProjectURL else { return }
        NSLog("syncProject: start %@", projectURL.lastPathComponent)
        gitChangesStore.setPreferredDirectory(projectURL)
        fileExplorerStore.setProject(projectURL)
        NSLog("syncProject: setProject done %.0fms", (CFAbsoluteTimeGetCurrent() - t0) * 1000)

        // Switch terminal workspace to this project
        if let activeID = projectStore.activeProjectID {
            FileManager.default.changeCurrentDirectoryPath(projectURL.path)
            workspaceStore.switchProject(activeID)
            NSLog("syncProject: switchProject done %.0fms", (CFAbsoluteTimeGetCurrent() - t0) * 1000)
        }

        // Fetch current branch immediately for sidebar display
        // (don't wait for Git tab to be opened)
        Task {
            let git = GitService(workingDirectory: projectURL)
            if let branch = try? await git.getCurrentBranch(),
               let activeID = projectStore.activeProjectID {
                projectStore.updateProjectBranch(activeID, branch: branch)
            }
        }
    }
}
