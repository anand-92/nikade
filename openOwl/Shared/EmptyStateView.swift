import SwiftUI

/// Reusable empty state placeholder with app icon, title, and optional subtitle.
struct EmptyStateView: View {
    let title: String
    var subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(spacing: 12) {
            if let icon = NSApp?.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .opacity(0.15)
            }
            Text(title)
                .font(AppFonts.primaryLabel)
                .foregroundStyle(AppPalette.textSecondary)
            if let subtitle {
                Text(subtitle)
                    .font(AppFonts.caption)
                    .foregroundStyle(AppPalette.textTertiary)
            }
        }
    }
}
