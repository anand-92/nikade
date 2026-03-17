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
    static let contentMinWidth: CGFloat = 400
    static let windowMinWidth: CGFloat = 800
    static let windowMinHeight: CGFloat = 500
}

// MARK: - Design System

/// 暗色调色盘 — 4 层背景 + 3 层文字 + 边框 + 强调色
enum AppPalette {
    // 背景 4 层
    static let base      = Color(nsColor: NSColor(red: 0.078, green: 0.078, blue: 0.086, alpha: 1)) // #141416
    static let surface   = Color(nsColor: NSColor(red: 0.110, green: 0.110, blue: 0.122, alpha: 1)) // #1c1c1f
    static let elevated  = Color(nsColor: NSColor(red: 0.141, green: 0.141, blue: 0.157, alpha: 1)) // #242428
    static let overlay   = Color(nsColor: NSColor(red: 0.173, green: 0.173, blue: 0.192, alpha: 1)) // #2c2c31

    // 文字 3 层
    static let textPrimary   = Color(nsColor: NSColor(white: 0.91, alpha: 1))
    static let textSecondary = Color(nsColor: NSColor(white: 0.56, alpha: 1))
    static let textTertiary  = Color(nsColor: NSColor(white: 0.35, alpha: 1))

    // 边框
    static let border      = Color.white.opacity(0.06)
    static let borderHover = Color.white.opacity(0.12)

    // 强调色
    static let accent = Color(nsColor: NSColor(red: 0.42, green: 0.71, blue: 0.93, alpha: 1))

    // NSColor 变体 — 供 CodeEditSourceEditor 等需要 NSColor 的 API 使用
    enum ns {
        static let surface   = NSColor(red: 0.110, green: 0.110, blue: 0.122, alpha: 1)
        static let elevated  = NSColor(red: 0.141, green: 0.141, blue: 0.157, alpha: 1)
        static let textPrimary = NSColor(white: 0.91, alpha: 1)
        static let accent    = NSColor(red: 0.42, green: 0.71, blue: 0.93, alpha: 1)
    }
}

enum AppColors {
    /// 选中/活动态背景
    static let activeBackground = AppPalette.accent.opacity(0.12)
    /// 悬停态背景
    static let hoverBackground = Color.white.opacity(0.05)
    /// 选中边框
    static let selectedBorder = AppPalette.accent

    // 状态色
    static let error = Color.red
    static let warning = Color.orange
    static let success = Color.green
}

enum AppFonts {
    static let title         = Font.system(size: 16, weight: .semibold)
    static let sectionHeader = Font.system(size: 10, weight: .semibold)
    static let sectionTracking: CGFloat = 1.5
    static let primaryLabel  = Font.system(size: 12, weight: .medium)
    static let secondaryLabel = Font.system(size: 11)
    static let body          = Font.system(size: 12)
    static let mono          = Font.system(size: 11, design: .monospaced)
    static let badge         = Font.system(size: 9, weight: .medium)
    static let caption       = Font.system(size: 10)
    static let statusBar     = Font.system(size: 11)
}

enum AppSpacing {
    static let cornerRadius: CGFloat = 6
    static let cornerRadiusSmall: CGFloat = 4
    static let itemGap: CGFloat = 6
    static let panelPadding: CGFloat = 12
    static let headerHeight: CGFloat = 32
    static let statusBarHeight: CGFloat = 28
    static let editorTabBarHeight: CGFloat = 28
    static let listRowHeight: CGFloat = 26
}
