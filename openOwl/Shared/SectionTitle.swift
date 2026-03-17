import SwiftUI

/// 统一分区标题样式 — 大写字母 + tracking + tertiary 色
struct SectionTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(AppFonts.sectionHeader)
            .tracking(AppFonts.sectionTracking)
            .foregroundStyle(AppPalette.textTertiary)
    }
}
