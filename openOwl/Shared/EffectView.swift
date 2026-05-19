import AppKit
import SwiftUI

/// NSVisualEffectView wrapper, based on CodeEdit's EffectView implementation.
/// Migrated to `.background(.regularMaterial)`, which macOS Tahoe automatically upgrades to Liquid Glass.
@available(*, deprecated, message: "Use .background(.regularMaterial) instead")
struct EffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow
    var isEmphasized: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.isEmphasized = isEmphasized
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.isEmphasized = isEmphasized
        nsView.state = .followsWindowActiveState
    }
}
