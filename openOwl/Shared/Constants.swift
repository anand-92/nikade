import Foundation
import SwiftUI

enum AppConstants {
    static let appName = "openOwl"
    static let bundleIdentifier = "com.openowl.app"

    // Ghostty
    static let termEnv = "xterm-ghostty"
    static let ghosttyResourcesDirEnv = "GHOSTTY_RESOURCES_DIR"

    // Layout
    static let sidebarWidth: CGFloat = 250
    static let headerHeight: CGFloat = 28          // 同 CodeEdit tab bar 高度
    static let terminalToolbarHeight: CGFloat = 28 // 同 CodeEdit
    static let contentMinWidth: CGFloat = 400
    static let windowMinWidth: CGFloat = 800
    static let windowMinHeight: CGFloat = 500
}

// MARK: - Design System (参照 CodeEdit)

enum AppColors {
    /// 选中/活动态背景
    static let activeBackground = Color.accentColor.opacity(0.15)
    /// 悬停态背景
    static let hoverBackground = Color.secondary.opacity(0.08)

    // 状态色
    static let error = Color.red
    static let warning = Color.orange
    static let success = Color.green
}

enum AppFonts {
    static let sectionHeader = Font.system(size: 11, weight: .semibold)
    static let primaryLabel = Font.system(size: 12, weight: .medium)
    static let secondaryLabel = Font.system(size: 11)
    static let badge = Font.system(size: 9, weight: .medium)
    static let caption = Font.system(size: 10)
    static let statusBar = Font.system(size: 11)
}

enum AppSpacing {
    static let cornerRadius: CGFloat = 6
    static let itemGap: CGFloat = 6
    static let statusBarHeight: CGFloat = 28
    static let editorTabBarHeight: CGFloat = 28
}
