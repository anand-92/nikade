import AppKit
import Combine

/// Manages the ghostty_app_t lifecycle and provides runtime callbacks.
/// Injected as @EnvironmentObject throughout the SwiftUI view hierarchy.
final class GhosttyAppManager: ObservableObject {
    @Published private(set) var isReady = false
    @Published private(set) var error: String?

    private(set) var app: ghostty_app_t?
    private var config: GhosttyConfig?

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
            // Handle terminal actions (title changes, notifications, etc.)
            return false
        }

        runtime.read_clipboard_cb = { userdata, clipboard, requestData in
            guard let userdata else { return false }
            let manager = Unmanaged<GhosttyAppManager>.fromOpaque(userdata).takeUnretainedValue()
            guard let surface = manager.activeSurface else { return false }

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
            return true
        }

        runtime.confirm_read_clipboard_cb = nil

        runtime.write_clipboard_cb = { userdata, clipboard, content, count, confirm in
            guard let content, count > 0 else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            let text = String(cString: content.pointee.data)
            pasteboard.setString(text, forType: .string)
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
}
