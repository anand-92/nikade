import AppKit
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    weak var ghosttyManager: GhosttyAppManager?
    var workspaceStore: TerminalWorkspaceStore?
    weak var navigationStore: AppNavigationStore?
    weak var deploymentStore: DeploymentStore?
    weak var projectStore: ProjectStore?
    private var localKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        ensureEditMenu()
        installLocalKeyMonitor()
    }

    /// SwiftUI sometimes omits the Edit menu. Ensure Cut/Copy/Paste/Select All exist
    /// so that TextField and TextEditor support Cmd+C/V/X/A.
    private func ensureEditMenu() {
        guard let mainMenu = NSApp.mainMenu else { return }

        // Check if Edit menu already exists
        if mainMenu.item(withTitle: "Edit") != nil { return }

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editMenuItem.submenu = editMenu

        // Insert after the app menu (index 1)
        let insertIndex = min(1, mainMenu.items.count)
        mainMenu.insertItem(editMenuItem, at: insertIndex)
    }

    deinit {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func installLocalKeyMonitor() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleLocalKeyDown(event) ? nil : event
        }
    }

    private func handleLocalKeyDown(_ event: NSEvent) -> Bool {
        guard let workspaceStore else { return false }

        let flags = event.modifierFlags.intersection([.command, .shift, .control, .option])
        guard flags.contains(.command) else { return false }
        guard !flags.contains(.control), !flags.contains(.option) else { return false }

        // Cmd+number: global project/worktree switch.
        // Switches terminal, sidebar, cwd, git, and files all at once.
        if let chars = event.charactersIgnoringModifiers?.lowercased(),
           let tabNumber = Int(chars), (1...9).contains(tabNumber),
           !flags.contains(.shift) {
            guard let projectStore else { return false }
            let tabs = projectStore.orderedProjectTabs
            let index = tabNumber - 1
            guard index < tabs.count else { return true }
            navigationStore?.navigate(to: .terminal)
            projectStore.activateProject(id: tabs[index].id)
            return true
        }

        // Cmd+Shift+Return: toggle maximize/restore current pane
        if flags == [.command, .shift], event.keyCode == 36 {
            workspaceStore.toggleMaximizeCurrentPane()
            return true
        }

        // All other terminal shortcuts only work when terminal is active
        guard navigationStore?.activeTab == .terminal else { return false }

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
