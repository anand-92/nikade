import AppKit
import SwiftUI

/// Centralized file icon and color mapping — eliminates duplication across
/// FileExplorerView, QuickOpenSheet, and OutlineTreeCellView.
enum FileIcons {
    static func iconName(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "md", "txt", "log": return "doc.text"
        case "json", "yml", "yaml", "toml", "plist": return "curlybraces"
        case "png", "jpg", "jpeg", "gif", "webp", "svg": return "photo"
        case "sh", "zsh", "bash": return "terminal"
        case "js", "ts", "tsx", "jsx": return "chevron.left.forwardslash.chevron.right"
        default: return "doc"
        }
    }

    static func iconColor(for url: URL) -> Color {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "swift": return Color(nsColor: .systemOrange)
        case "js", "ts", "tsx", "jsx": return Color(nsColor: .systemYellow)
        case "py": return Color(nsColor: .systemGreen)
        case "json", "yml", "yaml": return Color(nsColor: .systemPurple)
        default: return .secondary
        }
    }
}
