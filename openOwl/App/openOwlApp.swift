import SwiftUI

@main
struct openOwlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var ghosttyManager: GhosttyAppManager
    @State private var workspaceStore = TerminalWorkspaceStore()
    @State private var navigationStore = AppNavigationStore()
    @State private var projectStore: ProjectStore
    @State private var gitChangesStore = GitChangesStore()
    @State private var fileExplorerStore = FileExplorerStore()
    @State private var deploymentStore = DeploymentStore()
    @State private var claudeStatusStore = ClaudeStatusStore()

    init() {
        Self.setupEnvironment()

        // Set cwd to active project BEFORE ghostty starts, so the first shell
        // opens in the project directory instead of ~
        let store = ProjectStore()
        if let url = store.activeProjectURL {
            FileManager.default.changeCurrentDirectoryPath(url.path)
        }
        _projectStore = State(wrappedValue: store)
        _ghosttyManager = State(wrappedValue: GhosttyAppManager())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(ghosttyManager)
                .environment(workspaceStore)
                .environment(navigationStore)
                .environment(projectStore)
                .environment(gitChangesStore)
                .environment(fileExplorerStore)
                .environment(deploymentStore)
                .environment(claudeStatusStore)
                .onAppear {
                    appDelegate.workspaceStore = workspaceStore
                    appDelegate.ghosttyManager = ghosttyManager
                    appDelegate.navigationStore = navigationStore
                    appDelegate.deploymentStore = deploymentStore
                    appDelegate.projectStore = projectStore
                    deploymentStore.recoverRunningDeployments()
                    ghosttyManager.onPaneTitleChanged = { paneID, title in
                        workspaceStore.updateTitle(for: paneID, title: title)
                    }
                    ghosttyManager.onPaneBell = { paneID in
                        let isTerminalVisible = navigationStore.activeTab == .terminal
                        workspaceStore.handleBell(paneID: paneID, isTerminalVisible: isTerminalVisible)
                    }
                    syncActiveProjectContext()
                    UpdateChecker.shared.checkOnLaunchIfNeeded()
                    claudeStatusStore.startPollingIfNeeded()
                }
                .onDisappear {
                    claudeStatusStore.stopPolling()
                }
                .onChange(of: projectStore.activeProjectID) { _, _ in
                    syncActiveProjectContext()
                }
                .onChange(of: navigationStore.activeTab) { _, _ in
                    syncActiveProjectContext()
                }
                .onChange(of: gitChangesStore.statusSnapshot?.branch) { _, _ in
                    // Fires on branch change within the same repo (e.g. checkout)
                    updateActiveBranchLabel()
                }
                .onChange(of: gitChangesStore.statusSnapshot?.repositoryRoot) { _, _ in
                    // Fires when the repo root changes (e.g. switching projects that both
                    // have a 'main' branch — branch string alone wouldn't change, so we
                    // need this second observer to keep the sidebar label in sync).
                    updateActiveBranchLabel()
                }
                .frame(
                    minWidth: AppConstants.windowMinWidth,
                    minHeight: AppConstants.windowMinHeight
                )
        }
        .defaultSize(width: 1200, height: 800)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton()
            }
        }

        MenuBarExtra("openOwl", image: "MenuBarIcon") {
            DeploymentTrayMenu()
                .environment(deploymentStore)
                .environment(navigationStore)
                .environment(projectStore)
        }
        .menuBarExtraStyle(.menu)

        Window("Update Available", id: "update") {
            UpdateAlertView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 400, height: 250)
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
    private func updateActiveBranchLabel() {
        guard let snapshot = gitChangesStore.statusSnapshot,
              let activeID = projectStore.activeProjectID,
              let activeURL = projectStore.activeProjectURL,
              snapshot.repositoryRoot.standardizedFileURL == activeURL.standardizedFileURL
        else { return }
        projectStore.updateProjectBranch(activeID, branch: snapshot.branch)
    }

    @MainActor
    private func syncActiveProjectContext() {
        guard let projectURL = projectStore.activeProjectURL,
              let activeID = projectStore.activeProjectID else { return }

        // Always update cwd (needed for new terminal surfaces)
        FileManager.default.changeCurrentDirectoryPath(projectURL.path)

        // Only refresh the currently visible tab's store
        switch navigationStore.activeTab {
        case .terminal:
            workspaceStore.switchProject(activeID)
        case .fileExplorer:
            fileExplorerStore.setProject(projectURL)
        case .gitChanges:
            gitChangesStore.setPreferredDirectory(projectURL)
        case .deployments:
            break
        }
    }
}
