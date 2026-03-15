import SwiftUI

/// 语义化分割线。当前直接使用系统 Divider，
/// macOS 的 separatorColor 已自适应暗/亮模式。
struct PanelDivider: View {
    var body: some View {
        Divider()
    }
}
