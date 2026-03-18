import SwiftUI

// MARK: - Liquid Glass Compatibility Helpers (macOS 26+)

extension View {
    /// Apply `.glassEffect(.regular)` on macOS 26+, no-op on older versions.
    @ViewBuilder
    func glassEffectIfAvailable<S: Shape>(
        _ active: Bool = true,
        in shape: S
    ) -> some View {
        if #available(macOS 26, *), active {
            self.glassEffect(.regular, in: shape)
        } else {
            self
        }
    }

    /// Apply `.glassEffect(.regular.tint(...))` on macOS 26+, fallback to a custom style on older versions.
    @ViewBuilder
    func glassEffectWithTint<S: Shape>(
        _ active: Bool,
        tint: Color = .accentColor,
        in shape: S,
        fallback: some View
    ) -> some View {
        if #available(macOS 26, *), active {
            self.glassEffect(.regular.tint(tint), in: shape)
        } else {
            self.background { fallback }
        }
    }
}
