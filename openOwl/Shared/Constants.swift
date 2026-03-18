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

/// 语义调色盘 — 自适应亮/暗模式，尊重用户系统设置
enum AppPalette {
    // 背景 4 层（system semantic colors adapt to light/dark mode）
    static let base      = Color(nsColor: .windowBackgroundColor)
    static let surface   = Color(nsColor: .controlBackgroundColor)
    static let elevated  = Color(nsColor: .underPageBackgroundColor)
    static let overlay   = Color(nsColor: .controlBackgroundColor)

    // 文字 3 层
    static let textPrimary: Color   = .primary
    static let textSecondary: Color = .secondary
    static let textTertiary  = Color(nsColor: .tertiaryLabelColor)

    // 边框
    static let border      = Color(nsColor: .separatorColor)
    static let borderHover = Color(nsColor: .quaternaryLabelColor)

    // 强调色（respects user's system accent color）
    static let accent: Color = .accentColor

    // NSColor 变体 — 供 CodeEditSourceEditor 等需要 NSColor 的 API 使用
    enum ns {
        static let surface: NSColor   = .controlBackgroundColor
        static let elevated: NSColor  = .underPageBackgroundColor
        static let textPrimary: NSColor = .labelColor
        static let accent: NSColor    = .controlAccentColor
    }
}

enum AppColors {
    /// 选中/活动态背景
    static let activeBackground = Color.accentColor.opacity(0.12)
    /// 悬停态背景
    static let hoverBackground = Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    /// 选中边框
    static let selectedBorder: Color = .accentColor

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
