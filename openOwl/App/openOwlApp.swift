import SwiftUI

@main
struct openOwlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var ghosttyManager = GhosttyAppManager()

    init() {
        setupEnvironment()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ghosttyManager)
                .frame(
                    minWidth: AppConstants.windowMinWidth,
                    minHeight: AppConstants.windowMinHeight
                )
        }
        .defaultSize(width: 1200, height: 800)
    }

    private func setupEnvironment() {
        setenv("TERM", AppConstants.termEnv, 1)

        // GHOSTTY_RESOURCES_DIR: ghostty needs this for terminfo, shell-integration, themes.
        // In dev builds, use the symlinked ghostty-resources in the project root.
        // In release builds, bundle resources inside the .app.
        if let resourcesInBundle = Bundle.main.resourcePath {
            let ghosttyRes = (resourcesInBundle as NSString).appendingPathComponent("ghostty")
            if FileManager.default.fileExists(atPath: ghosttyRes) {
                setenv(AppConstants.ghosttyResourcesDirEnv, ghosttyRes, 1)
                return
            }
        }

        // Dev fallback: project root's ghostty-resources symlink
        let execPath = Bundle.main.bundlePath
        // Walk up from .app bundle to find project root
        var dir = (execPath as NSString).deletingLastPathComponent
        for _ in 0..<5 {
            let candidate = (dir as NSString).appendingPathComponent("ghostty-resources")
            if FileManager.default.fileExists(atPath: candidate) {
                setenv(AppConstants.ghosttyResourcesDirEnv, candidate, 1)
                return
            }
            dir = (dir as NSString).deletingLastPathComponent
        }
    }
}
