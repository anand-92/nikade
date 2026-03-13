import AppKit
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    weak var ghosttyManager: GhosttyAppManager?
    var workspaceStore: TerminalWorkspaceStore?
    weak var navigationStore: AppNavigationStore?
    private var localKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // #region agent log
        debugLog("AppDelegate.swift:didFinishLaunching", "applicationDidFinishLaunching called", ["hypothesisId": "H10", "activationPolicy": "\(NSApp.activationPolicy().rawValue)"])
        // #endregion
        // Ensure the app activates properly
        NSApp.setActivationPolicy(.regular)
        // #region agent log
        debugLog("AppDelegate.swift:didFinishLaunching-after-policy", "activation policy set", ["hypothesisId": "H10", "activationPolicy": "\(NSApp.activationPolicy().rawValue)", "windowCount": NSApp.windows.count])
        // #endregion
        installLocalKeyMonitor()
        // #region agent log
        installWindowObservers()
        // #endregion
    }

    // #region agent log
    private func installWindowObservers() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { notif in
            let win = notif.object as? NSWindow
            debugLog("AppDelegate.swift:window-willClose", "window will close", ["hypothesisId": "H7", "windowTitle": win?.title ?? "nil", "windowCount": NSApp.windows.count])
        }
        nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { notif in
            let win = notif.object as? NSWindow
            debugLog("AppDelegate.swift:window-didBecomeKey", "window became key", ["windowTitle": win?.title ?? "nil", "windowCount": NSApp.windows.count])
        }
        nc.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { notif in
            let win = notif.object as? NSWindow
            debugLog("AppDelegate.swift:window-didResignKey", "window resigned key", ["windowTitle": win?.title ?? "nil", "windowCount": NSApp.windows.count])
        }
        nc.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            debugLog("AppDelegate.swift:app-willTerminate", "app will terminate via notification", ["hypothesisId": "H7", "windowCount": NSApp.windows.count])
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            let windows = NSApp.windows
            debugLog("AppDelegate.swift:window-check-2s", "window check after 2s", ["hypothesisId": "H7", "windowCount": windows.count, "windowDetails": windows.map { "[\($0.title):\($0.isVisible):\($0.frame)]" }.joined(separator: ", ")])
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            let windows = NSApp.windows
            debugLog("AppDelegate.swift:window-check-5s", "window check after 5s", ["hypothesisId": "H7", "windowCount": windows.count, "windowDetails": windows.map { "[\($0.title):\($0.isVisible):\($0.frame)]" }.joined(separator: ", ")])
        }
    }
    // #endregion

    deinit {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // #region agent log
        debugLog("AppDelegate.swift:shouldTerminate", "applicationShouldTerminateAfterLastWindowClosed called", ["hypothesisId": "H7"])
        // #endregion
        return true
    }

    // #region agent log
    func applicationWillTerminate(_ notification: Notification) {
        debugLog("AppDelegate.swift:willTerminate", "applicationWillTerminate called", ["hypothesisId": "H7"])
    }
    // #endregion

    private func installLocalKeyMonitor() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleLocalKeyDown(event) ? nil : event
        }
    }

    private func handleLocalKeyDown(_ event: NSEvent) -> Bool {
        guard let workspaceStore else { return false }
        if navigationStore?.selection != .terminal { return false }

        let flags = event.modifierFlags.intersection([.command, .shift, .control, .option])
        guard flags.contains(.command) else { return false }
        guard !flags.contains(.control), !flags.contains(.option) else { return false }

        switch event.keyCode {
        case 123:
            workspaceStore.focusNeighbor(.left)
            return true
        case 124:
            workspaceStore.focusNeighbor(.right)
            return true
        case 125:
            workspaceStore.focusNeighbor(.down)
            return true
        case 126:
            workspaceStore.focusNeighbor(.up)
            return true
        default:
            break
        }

        guard let chars = event.charactersIgnoringModifiers?.lowercased() else { return false }

        switch chars {
        case "t":
            workspaceStore.newTab()
            return true
        case "w":
            if workspaceStore.closeCurrent() == .closeWindow {
                NSApp.keyWindow?.performClose(nil)
            }
            return true
        case "d":
            if flags.contains(.shift) {
                workspaceStore.splitCurrent(axis: .vertical)
            } else {
                workspaceStore.splitCurrent(axis: .horizontal)
            }
            return true
        case "1", "2", "3", "4", "5", "6", "7", "8", "9":
            guard let tabNumber = Int(chars) else { return false }
            workspaceStore.selectTab(index: tabNumber - 1)
            return true
        default:
            return false
        }
    }
}

// MARK: - Keyboard Routing

extension AppDelegate {
    /// Route key events to the focused terminal NSView, bypassing SwiftUI's event handling.
    /// Without this, SwiftUI intercepts keys like arrow keys, Tab, Escape, etc.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                window.makeKeyAndOrderFront(self)
            }
        }
        return true
    }
}
