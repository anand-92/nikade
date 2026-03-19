import AppKit
import Darwin
import Observation

/// Manages the ghostty_app_t lifecycle and provides runtime callbacks.
/// Injected via .environment() throughout the SwiftUI view hierarchy.
@Observable
final class GhosttyAppManager {
    private(set) var isReady = false
    private(set) var error: String?

    private(set) var app: ghostty_app_t?
    private var config: GhosttyConfig?
    private var paneSurfaceMap: [UUID: ghostty_surface_t] = [:]
    private var paneViewMap: [UUID: WeakTerminalView] = [:]
    private var paneScrollViewMap: [UUID: WeakScrollView] = [:]
    /// Strong references to TerminalNSViews so they survive SwiftUI view dismantling.
    /// Removed only when a pane is explicitly closed via destroyPane(_:).
    private var retainedTerminalViews: [UUID: TerminalNSView] = [:]

    private(set) var launchProfile = GhosttyLaunchProfile(
        configCommand: nil,
        fallbackShell: "/bin/zsh"
    )
    var onPaneTitleChanged: ((UUID, String) -> Void)?
    var onPaneBell: ((UUID) -> Void)?
    var onSearchEnd: ((UUID) -> Void)?
    var onSearchTotal: ((UUID, UInt?) -> Void)?
    var onSearchSelected: ((UUID, UInt?) -> Void)?

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

        runtime.read_clipboard_cb = { userdata, clipboard, state in
            guard let userdata else { return false }
            let manager = Unmanaged<GhosttyAppManager>.fromOpaque(userdata).takeUnretainedValue()
            guard manager.activeSurface != nil else { return false }

            // Must defer completion to avoid reentrancy crash:
            // ghostty_surface_key → paste binding → read_clipboard_cb →
            // ghostty_surface_complete_clipboard_request would crash if synchronous.
            DispatchQueue.main.async {
                // Re-read activeSurface: the surface captured at callback entry may
                // have been freed (pane closed) before this async block runs.
                guard let surface = manager.activeSurface else { return }
                let value = NSPasteboard.general.string(forType: .string) ?? ""
                value.withCString { ptr in
                    ghostty_surface_complete_clipboard_request(surface, ptr, state, false)
                }
            }
            return true
        }

        runtime.confirm_read_clipboard_cb = { userdata, content, state, _ in
            guard let content else { return }
            guard let userdata else { return }
            // Copy content before async dispatch — libghostty may free the buffer after callback returns.
            let contentStr = String(cString: content)
            DispatchQueue.main.async {
                let manager = Unmanaged<GhosttyAppManager>.fromOpaque(userdata).takeUnretainedValue()
                guard let surface = manager.activeSurface else { return }
                contentStr.withCString { ptr in
                    ghostty_surface_complete_clipboard_request(surface, ptr, state, true)
                }
            }
        }

        runtime.write_clipboard_cb = { _, clipboard, content, count, _ in
            guard let content, count > 0 else { return }
            let buffer = UnsafeBufferPointer(start: content, count: Int(count))

            // Find text/plain content, or fall back to first available
            var fallback: String?
            for item in buffer {
                guard let dataPtr = item.data else { continue }
                let value = String(cString: dataPtr)

                if let mimePtr = item.mime {
                    let mime = String(cString: mimePtr)
                    if mime.hasPrefix("text/plain") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(value, forType: .string)
                        return
                    }
                }
                if fallback == nil { fallback = value }
            }

            if let fallback {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(fallback, forType: .string)
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

    // MARK: - Background tick timer

    private var backgroundTickTimer: Timer?

    /// Ensure ghostty events (bell, title changes) are processed even when the app
    /// is inactive. macOS may delay DispatchQueue.main.async for background apps,
    /// so we run a low-frequency timer to call tick() while backgrounded.
    func startBackgroundTick() {
        guard backgroundTickTimer == nil else { return }
        backgroundTickTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(backgroundTickTimer!, forMode: .common)
    }

    func stopBackgroundTick() {
        backgroundTickTimer?.invalidate()
        backgroundTickTimer = nil
    }

    var configSnapshot: GhosttyConfigSnapshot? {
        config?.snapshot
    }

    func register(surface: ghostty_surface_t, for paneID: UUID, view: TerminalNSView) {
        paneSurfaceMap[paneID] = surface
        paneViewMap[paneID] = WeakTerminalView(view)
        retainedTerminalViews[paneID] = view
        activeSurface = surface
    }

    func registerScrollView(_ scrollView: TerminalScrollView, for paneID: UUID) {
        paneScrollViewMap[paneID] = WeakScrollView(scrollView)
    }

    func unregisterPane(_ paneID: UUID) {
        if let surface = paneSurfaceMap.removeValue(forKey: paneID), activeSurface == surface {
            activeSurface = nil
        }
        paneViewMap.removeValue(forKey: paneID)
        paneScrollViewMap.removeValue(forKey: paneID)
    }

    /// Explicitly destroy a pane's terminal surface and release the retained view.
    /// Called when a pane is actually closed (not just hidden by SwiftUI lifecycle).
    func destroyPane(_ paneID: UUID) {
        if let view = retainedTerminalViews.removeValue(forKey: paneID) {
            view.destroySurface()
        }
        unregisterPane(paneID)
    }

    func terminalView(for paneID: UUID) -> TerminalNSView? {
        paneViewMap[paneID]?.value
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
        // All callbacks are called synchronously — tick() already runs on the main
        // thread (via Timer or wakeup_cb). Using DispatchQueue.main.async would cause
        // macOS to delay delivery for backgrounded apps, breaking notifications.
        switch action.tag {
        case GHOSTTY_ACTION_SET_TITLE, GHOSTTY_ACTION_SET_TAB_TITLE:
            guard let title = titleFromAction(action) else { return false }
            guard let paneID = paneID(for: target) else { return false }
            onPaneTitleChanged?(paneID, title)
            return false

        case GHOSTTY_ACTION_SCROLLBAR:
            guard let paneID = paneID(for: target) else { return false }
            let v = action.action.scrollbar
            let state = TerminalScrollbarState(total: v.total, offset: v.offset, len: v.len)
            paneScrollViewMap[paneID]?.value?.updateScrollbar(state)
            return true

        case GHOSTTY_ACTION_CELL_SIZE:
            guard let paneID = paneID(for: target) else { return false }
            let v = action.action.cell_size
            let size = CGSize(width: CGFloat(v.width), height: CGFloat(v.height))
            paneScrollViewMap[paneID]?.value?.updateCellSize(size)
            return true

        case GHOSTTY_ACTION_RING_BELL:
            guard let paneID = paneID(for: target) else { return false }
            onPaneBell?(paneID)
            return true

        case GHOSTTY_ACTION_START_SEARCH:
            // Return false — we handle Cmd+F ourselves via performKeyEquivalent.
            // Ghostty triggers this when its own keybinding fires; we don't need it.
            return false

        case GHOSTTY_ACTION_END_SEARCH:
            guard let paneID = paneID(for: target) else { return false }
            onSearchEnd?(paneID)
            return true

        case GHOSTTY_ACTION_SEARCH_TOTAL:
            guard let paneID = paneID(for: target) else { return false }
            let raw = action.action.search_total.total
            let total: UInt? = raw >= 0 ? UInt(raw) : nil
            onSearchTotal?(paneID, total)
            return true

        case GHOSTTY_ACTION_SEARCH_SELECTED:
            guard let paneID = paneID(for: target) else { return false }
            let raw = action.action.search_selected.selected
            let selected: UInt? = raw >= 0 ? UInt(raw) : nil
            onSearchSelected?(paneID, selected)
            return true

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

private final class WeakScrollView {
    weak var value: TerminalScrollView?

    init(_ value: TerminalScrollView?) {
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
