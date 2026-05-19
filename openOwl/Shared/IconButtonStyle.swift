import SwiftUI

/// Icon button style, based on CodeEdit's IconButtonStyle.
/// Standard 24x24pt size with 14.5pt icon, supports active/pressed states.
struct IconButtonStyle: ButtonStyle {
    var isActive: Bool = false
    var font: Font = .system(size: 14.5)
    var size: CGSize = CGSize(width: 24, height: 24)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .symbolVariant(isActive ? .fill : .none)
            .foregroundColor(isActive ? .accentColor : .secondary)
            .frame(width: size.width, height: size.height)
            .brightness(configuration.isPressed ? -0.1 : 0)
    }
}

extension ButtonStyle where Self == IconButtonStyle {
    static func icon(
        isActive: Bool = false,
        font: Font? = nil,
        size: CGFloat = 24
    ) -> IconButtonStyle {
        IconButtonStyle(
            isActive: isActive,
            font: font ?? .system(size: 14.5),
            size: CGSize(width: size, height: size)
        )
    }
}
