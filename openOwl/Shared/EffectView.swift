import AppKit
import SwiftUI

/// NSVisualEffectView 包装，参照 CodeEdit 的 EffectView 实现。
/// 已迁移到 `.background(.regularMaterial)`，macOS Tahoe 会自动升级为 Liquid Glass。
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
