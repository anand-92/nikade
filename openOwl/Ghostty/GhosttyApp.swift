import AppKit
import Combine
import Darwin

/// Manages the ghostty_app_t lifecycle and provides runtime callbacks.
/// Injected as @EnvironmentObject throughout the SwiftUI view hierarchy.
final class GhosttyAppManager: ObservableObject {
    @Published private(set) var isReady = false
    @Published private(set) var error: String?

    private(set) var app: ghostty_app_t?
    private var config: GhosttyConfig?
    private var paneSurfaceMap: [UUID: ghostty_surface_t] = [:]
    private var paneViewMap: [UUID: WeakTerminalView] = [:]

    private(set) var launchProfile = GhosttyLaunchProfile(
        configCommand: nil,
        fallbackShell: "/bin/zsh"
    )
    var onPaneTitleChanged: ((UUID, String) -> Void)?

    /// Stores a reference to the active surface so clipboard callbacks can reach it.
    /// Updated when a TerminalNSView creates its surface.
    var activeSurface: ghostty_surface_t?

    init() {
        initializeGhostty()
    }

    deinit {
        if let app {
            ghostty_app_free(app)
        }
    }

    private func initializeGhostty() {
        // Initialize the ghostty library
        var args: [UnsafeMutablePointer<CChar>?] = []
        let appName = strdup("openOwl")
        args.append(appName)

        let result = ghostty_init(1, &args)
        appName?.deallocate()

        guard result == GHOSTTY_SUCCESS else {
            error = "ghostty_init failed with code \(result)"
            return
        }

        // Create config
        config = GhosttyConfig()
        guard config?.config != nil else {
            error = "Failed to create ghostty config"
            return
        }
        launchProfile = GhosttyLaunchProfile(
            configCommand: config?.snapshot.command,
            fallbackShell: Self.detectFallbackShell()
        )
        NSLog(
            "openOwl: launch profile config-command=%@ fallback-shell=%@",
            launchProfile.configCommand ?? "<nil>",
            launchProfile.fallbackShell
        )

        // Setup runtime callbacks
        var runtime = ghostty_runtime_config_s()
        runtime.userdata = Unmanaged.passUnretained(self).toOpaque()
        runtime.supports_selection_clipboard = true

        runtime.wakeup_cb = { userdata in
            guard let userdata else { return }
            let manager = Unmanaged<GhosttyAppManager>.fromOpaque(userdata).takeUnretainedValue()
            DispatchQueue.main.async {
                manager.tick()
            }
        }

        runtime.action_cb = { app, target, action in
            guard let app else { return false }
            guard let userdata = ghostty_app_userdata(app) else { return false }
            let manager = Unmanaged<GhosttyAppManager>.fromOpaque(userdata).takeUnretainedValue()
            return manager.handleAction(target: target, action: action)
        }

        runtime.read_clipboard_cb = { userdata, clipboard, requestData in
            guard let userdata else { return false }
            let manager = Unmanaged<GhosttyAppManager>.fromOpaque(userdata).takeUnretainedValue()

            // Must complete clipboard request on main thread for NSPasteboard access
            let completeOnMain = {
                guard let surface = manager.activeSurface else { return }
                let pasteboard = NSPasteboard.general
                let content = pasteboard.string(forType: .string) ?? ""
                content.withCString { cstr in
                    ghostty_surface_complete_clipboard_request(
                        surface,
                        cstr,
                        requestData,
                        false
                    )
                }
            }

            if Thread.isMainThread {
                completeOnMain()
            } else {
                DispatchQueue.main.async { completeOnMain() }
            }
            return true
        }

        runtime.confirm_read_clipboard_cb = nil

        runtime.write_clipboard_cb = { userdata, clipboard, content, count, confirm in
            guard let content, count > 0 else { return }
            let doWrite = {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                let text = String(cString: content.pointee.data)
                pasteboard.setString(text, forType: .string)
            }
            if Thread.isMainThread {
                doWrite()
            } else {
                DispatchQueue.main.async { doWrite() }
            }
        }

        runtime.close_surface_cb = { userdata, confirm in
            NSLog("ghostty: surface close requested")
        }

        // Create app
        app = ghostty_app_new(&runtime, config!.config)
        guard app != nil else {
            error = "Failed to create ghostty app"
            return
        }

        isReady = true
    }

    /// Called from wakeup_cb to process pending ghostty events on the main thread.
    func tick() {
        guard let app else { return }
        ghostty_app_tick(app)
    }

    var configSnapshot: GhosttyConfigSnapshot? {
        config?.snapshot
    }

    func register(surface: ghostty_surface_t, for paneID: UUID, view: TerminalNSView) {
        paneSurfaceMap[paneID] = surface
        paneViewMap[paneID] = WeakTerminalView(view)
        activeSurface = surface
    }

    func unregisterPane(_ paneID: UUID) {
        if let surface = paneSurfaceMap.removeValue(forKey: paneID), activeSurface == surface {
            activeSurface = nil
        }
        paneViewMap.removeValue(forKey: paneID)
    }

    func focusPane(_ paneID: UUID) -> Bool {
        guard let view = paneViewMap[paneID]?.value else {
            paneViewMap.removeValue(forKey: paneID)
            return false
        }
        guard let window = view.window else { return false }
        window.makeKeyAndOrderFront(nil)
        return window.makeFirstResponder(view)
    }

    func surface(for paneID: UUID) -> ghostty_surface_t? {
        paneSurfaceMap[paneID]
    }

    private func handleAction(target: ghostty_target_s, action: ghostty_action_s) -> Bool {
        switch action.tag {
        case GHOSTTY_ACTION_SET_TITLE, GHOSTTY_ACTION_SET_TAB_TITLE:
            guard let title = titleFromAction(action) else { return false }
            guard let paneID = paneID(for: target) else { return false }

            DispatchQueue.main.async { [weak self] in
                self?.onPaneTitleChanged?(paneID, title)
            }
            return false

        default:
            return false
        }
    }

    private func titleFromAction(_ action: ghostty_action_s) -> String? {
        let rawTitle: UnsafePointer<CChar>?
        switch action.tag {
        case GHOSTTY_ACTION_SET_TITLE:
            rawTitle = action.action.set_title.title
        case GHOSTTY_ACTION_SET_TAB_TITLE:
            rawTitle = action.action.set_tab_title.title
        default:
            rawTitle = nil
        }

        guard let rawTitle else { return nil }
        let title = String(cString: rawTitle).trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private func paneID(for target: ghostty_target_s) -> UUID? {
        switch target.tag {
        case GHOSTTY_TARGET_SURFACE:
            return paneID(for: target.target.surface)

        case GHOSTTY_TARGET_APP:
            return paneID(for: activeSurface)

        default:
            return nil
        }
    }

    private func paneID(for surface: ghostty_surface_t?) -> UUID? {
        guard let surface else { return nil }
        for (paneID, mappedSurface) in paneSurfaceMap where mappedSurface == surface {
            return paneID
        }
        return nil
    }
}

struct GhosttyLaunchProfile {
    let configCommand: String?
    let fallbackShell: String

    var shouldInjectFallbackShell: Bool {
        configCommand == nil
    }
}

private final class WeakTerminalView {
    weak var value: TerminalNSView?

    init(_ value: TerminalNSView?) {
        self.value = value
    }
}

private extension GhosttyAppManager {
    static func detectFallbackShell() -> String {
        if let envShell = ProcessInfo.processInfo.environment["SHELL"], isExecutableFile(envShell) {
            return envShell
        }

        if let loginShell = loginShellPath(), isExecutableFile(loginShell) {
            return loginShell
        }

        return "/bin/zsh"
    }

    static func loginShellPath() -> String? {
        guard let passwd = getpwuid(getuid()) else { return nil }
        guard let shell = passwd.pointee.pw_shell else { return nil }
        let path = String(cString: shell)
        return path.isEmpty ? nil : path
    }

    static func isExecutableFile(_ path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }
}
