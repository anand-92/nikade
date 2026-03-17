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
        installTerminalMenu()
        installViewMenu()
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

    // MARK: - Terminal Menu

    private func installTerminalMenu() {
        guard let mainMenu = NSApp.mainMenu else { return }

        let menu = NSMenu(title: "Terminal")

        let newTab = NSMenuItem(title: "New Tab", action: #selector(menuNewTab), keyEquivalent: "t")
        menu.addItem(newTab)

        let closeTab = NSMenuItem(title: "Close Tab", action: #selector(menuCloseTab), keyEquivalent: "w")
        menu.addItem(closeTab)

        menu.addItem(.separator())

        let splitH = NSMenuItem(title: "Split Right", action: #selector(menuSplitHorizontal), keyEquivalent: "d")
        menu.addItem(splitH)

        let splitV = NSMenuItem(title: "Split Down", action: #selector(menuSplitVertical), keyEquivalent: "d")
        splitV.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(splitV)

        menu.addItem(.separator())

        let maximize = NSMenuItem(title: "Maximize Pane", action: #selector(menuToggleMaximize), keyEquivalent: "\r")
        maximize.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(maximize)

        menu.addItem(.separator())

        let focusLeft = NSMenuItem(title: "Focus Left", action: #selector(menuFocusLeft), keyEquivalent: "")
        focusLeft.keyEquivalent = String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))
        focusLeft.keyEquivalentModifierMask = [.command]
        menu.addItem(focusLeft)

        let focusRight = NSMenuItem(title: "Focus Right", action: #selector(menuFocusRight), keyEquivalent: "")
        focusRight.keyEquivalent = String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))
        focusRight.keyEquivalentModifierMask = [.command]
        menu.addItem(focusRight)

        let focusUp = NSMenuItem(title: "Focus Up", action: #selector(menuFocusUp), keyEquivalent: "")
        focusUp.keyEquivalent = String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
        focusUp.keyEquivalentModifierMask = [.command]
        menu.addItem(focusUp)

        let focusDown = NSMenuItem(title: "Focus Down", action: #selector(menuFocusDown), keyEquivalent: "")
        focusDown.keyEquivalent = String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
        focusDown.keyEquivalentModifierMask = [.command]
        menu.addItem(focusDown)

        let menuItem = NSMenuItem(title: "Terminal", action: nil, keyEquivalent: "")
        menuItem.submenu = menu
        let insertIndex = min(mainMenu.items.count, 3) // After Edit
        mainMenu.insertItem(menuItem, at: insertIndex)
    }

    // MARK: - View Menu

    private func installViewMenu() {
        guard let mainMenu = NSApp.mainMenu else { return }

        let menu = NSMenu(title: "View")

        let terminal = NSMenuItem(title: "Terminal", action: #selector(menuShowTerminal), keyEquivalent: "")
        menu.addItem(terminal)

        let git = NSMenuItem(title: "Git Changes", action: #selector(menuShowGit), keyEquivalent: "")
        menu.addItem(git)

        let files = NSMenuItem(title: "File Explorer", action: #selector(menuShowFiles), keyEquivalent: "")
        menu.addItem(files)

        let deploy = NSMenuItem(title: "Deployments", action: #selector(menuShowDeploy), keyEquivalent: "")
        menu.addItem(deploy)

        menu.addItem(.separator())

        let quickOpen = NSMenuItem(title: "Quick Open", action: #selector(menuQuickOpen), keyEquivalent: "p")
        menu.addItem(quickOpen)

        let menuItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        menuItem.submenu = menu
        let insertIndex = min(mainMenu.items.count, 4) // After Terminal
        mainMenu.insertItem(menuItem, at: insertIndex)
    }

    // MARK: - Menu Actions

    @objc private func menuNewTab() {
        workspaceStore?.newTab()
    }

    @objc private func menuCloseTab() {
        guard let workspaceStore else { return }
        if workspaceStore.closeCurrent() == .closeWindow {
            NSApp.keyWindow?.performClose(nil)
        }
    }

    @objc private func menuSplitHorizontal() {
        workspaceStore?.splitCurrent(axis: .horizontal)
    }

    @objc private func menuSplitVertical() {
        workspaceStore?.splitCurrent(axis: .vertical)
    }

    @objc private func menuToggleMaximize() {
        workspaceStore?.toggleMaximizeCurrentPane()
    }

    @objc private func menuFocusLeft() {
        workspaceStore?.focusNeighbor(.left)
    }

    @objc private func menuFocusRight() {
        workspaceStore?.focusNeighbor(.right)
    }

    @objc private func menuFocusUp() {
        workspaceStore?.focusNeighbor(.up)
    }

    @objc private func menuFocusDown() {
        workspaceStore?.focusNeighbor(.down)
    }

    @objc private func menuShowTerminal() {
        navigationStore?.navigate(to: .terminal)
    }

    @objc private func menuShowGit() {
        navigationStore?.navigate(to: .gitChanges)
    }

    @objc private func menuShowFiles() {
        navigationStore?.navigate(to: .fileExplorer)
    }

    @objc private func menuShowDeploy() {
        navigationStore?.navigate(to: .deployments)
    }

    @objc private func menuQuickOpen() {
        NotificationCenter.default.post(name: .quickOpen, object: nil)
    }

    // MARK: - Menu Validation
    // NSMenuItemValidation is implicitly conformed via NSObject

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let terminalOnly = navigationStore?.activeTab == .terminal

        switch menuItem.action {
        case #selector(menuNewTab), #selector(menuCloseTab),
             #selector(menuSplitHorizontal), #selector(menuSplitVertical),
             #selector(menuFocusLeft), #selector(menuFocusRight),
             #selector(menuFocusUp), #selector(menuFocusDown):
            return terminalOnly

        case #selector(menuToggleMaximize):
            if let ws = workspaceStore {
                menuItem.title = ws.maximizedPaneID != nil ? "Restore Pane" : "Maximize Pane"
            }
            return terminalOnly

        default:
            return true
        }
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
