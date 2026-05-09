import SwiftUI
import UserNotifications

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
    @State private var rightDockStore = RightDockStore()

    init() {
        Self.setupEnvironment()

        // ProjectStore loads projects and restores security-scoped bookmarks.
        // Working directory is passed directly to ghostty surface config via
        // TerminalPanel.workingDirectory — no need to change the app's process cwd
        // (which triggers macOS TCC prompts in dev builds).
        let store = ProjectStore()
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
                .environment(rightDockStore)
                .onAppear {
                    // Apply saved appearance preference (system/light/dark)
                    NSApp.appearance = AppAppearance.current.nsAppearance

                    appDelegate.workspaceStore = workspaceStore
                    appDelegate.ghosttyManager = ghosttyManager
                    appDelegate.navigationStore = navigationStore
                    appDelegate.deploymentStore = deploymentStore
                    appDelegate.projectStore = projectStore
                    appDelegate.rightDockStore = rightDockStore
                    deploymentStore.recoverRunningDeployments()
                    workspaceStore.destroyPaneHandler = { [weak ghosttyManager] paneID in
                        ghosttyManager?.destroyPane(paneID)
                    }
                    ghosttyManager.onPaneTitleChanged = { paneID, title in
                        workspaceStore.updateTitle(for: paneID, title: title)
                    }
                    ghosttyManager.onPaneBell = { paneID in
                        // Terminal occupies the center area unless the right dock is fullscreen.
                        let isTerminalVisible = !rightDockStore.isFullscreen
                        workspaceStore.handleBell(paneID: paneID, isTerminalVisible: isTerminalVisible)

                        // System-level feedback: sound, dock bounce, notification
                        let isPaneFocused = isTerminalVisible
                            && workspaceStore.activeTabID != nil
                            && workspaceStore.tabs.first(where: { $0.id == workspaceStore.activeTabID })?
                                .focusedPaneID == paneID

                        if !isPaneFocused {
                            NotificationSound.current.play()
                        }

                        if !NSApp.isActive {
                            NSApp.requestUserAttention(.informationalRequest)

                            let content = UNMutableNotificationContent()
                            content.title = "openOwl"
                            content.body = workspaceStore.paneTitles[paneID] ?? "Terminal task completed"
                            content.sound = .default
                            let request = UNNotificationRequest(
                                identifier: "bell-\(paneID.uuidString)",
                                content: content,
                                trigger: nil
                            )
                            UNUserNotificationCenter.current().add(request)
                        }
                    }
                    syncActiveProjectContext()
                    UpdateChecker.shared.checkOnLaunchIfNeeded()
                    claudeStatusStore.startPollingIfNeeded()
                }
                .onDisappear {
                    claudeStatusStore.stopPolling()
                    ghosttyManager.stopBackgroundTick()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                    ghosttyManager.startBackgroundTick()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    ghosttyManager.stopBackgroundTick()
                }
                .onChange(of: projectStore.activeProjectID) { _, _ in
                    syncActiveProjectContext()
                }
                .onChange(of: projectStore.activeFreeTerminalID) { _, _ in
                    syncActiveProjectContext()
                }
                .onChange(of: rightDockStore.isExpanded) { _, _ in
                    syncActiveProjectContext()
                }
                .onChange(of: rightDockStore.activeTab) { _, _ in
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

        Settings {
            SettingsView()
        }

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
        // Terminal namespace follows the sidebar selection — projects bind to their
        // working directory, free terminals share the user's home as cwd.
        switch projectStore.activeKind {
        case .project(let id):
            workspaceStore.switchNamespace(.project(id))
        case .freeTerminal(let id):
            workspaceStore.switchNamespace(.freeTerminal(id))
        case .none:
            workspaceStore.switchNamespace(nil)
        }

        // Right dock content stores only refresh when their tab is currently
        // visible AND a project is active (file explorer / git make no sense
        // for the free-terminal selection).
        guard let projectURL = projectStore.activeProjectURL,
              rightDockStore.isExpanded else { return }
        switch rightDockStore.activeTab {
        case .files:
            fileExplorerStore.setProject(projectURL)
        case .git:
            gitChangesStore.setPreferredDirectory(projectURL)
        case .deploy:
            break
        }
    }
}
