import SwiftUI

/// Unified section title style — Uppercase + tracking + tertiary color
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
