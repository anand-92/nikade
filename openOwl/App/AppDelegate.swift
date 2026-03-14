import AppKit
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    weak var ghosttyManager: GhosttyAppManager?
    var workspaceStore: TerminalWorkspaceStore?
    weak var navigationStore: AppNavigationStore?
    private var localKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        installLocalKeyMonitor()
    }

    deinit {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func installLocalKeyMonitor() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleLocalKeyDown(event) ? nil : event
        }
    }

    private func handleLocalKeyDown(_ event: NSEvent) -> Bool {
        guard let workspaceStore else { return false }
        if navigationStore?.activeTab != .terminal { return false }

        let flags = event.modifierFlags.intersection([.command, .shift, .control, .option])
        guard flags.contains(.command) else { return false }
        guard !flags.contains(.control), !flags.contains(.option) else { return false }

        switch event.keyCode {
        case 123: // Left arrow
            if flags.contains(.shift) {
                workspaceStore.swapPaneWithNeighbor(.left)
            } else {
                workspaceStore.focusNeighbor(.left)
            }
            return true
        case 124: // Right arrow
            if flags.contains(.shift) {
                workspaceStore.swapPaneWithNeighbor(.right)
            } else {
                workspaceStore.focusNeighbor(.right)
            }
            return true
        case 125: // Down arrow
            if flags.contains(.shift) {
                workspaceStore.swapPaneWithNeighbor(.down)
            } else {
                workspaceStore.focusNeighbor(.down)
            }
            return true
        case 126: // Up arrow
            if flags.contains(.shift) {
                workspaceStore.swapPaneWithNeighbor(.up)
            } else {
                workspaceStore.focusNeighbor(.up)
            }
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
