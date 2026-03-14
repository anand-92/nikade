import Foundation

enum AppConstants {
    static let appName = "openOwl"
    static let bundleIdentifier = "com.openowl.app"

    // Ghostty
    static let termEnv = "xterm-ghostty"
    static let ghosttyResourcesDirEnv = "GHOSTTY_RESOURCES_DIR"

    // Layout
    static let sidebarWidth: CGFloat = 250
    static let headerHeight: CGFloat = 36          // 对应 web 的 h-9
    static let terminalToolbarHeight: CGFloat = 28 // 对应 web 的 h-7
    static let contentMinWidth: CGFloat = 400
    static let windowMinWidth: CGFloat = 800
    static let windowMinHeight: CGFloat = 500
}
