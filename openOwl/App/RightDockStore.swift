import CoreGraphics
import Foundation
import Observation

enum RightDockTab: String, CaseIterable, Hashable, Identifiable {
    case files
    case git
    case deploy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .files: return "Files"
        case .git: return "Git"
        case .deploy: return "Deploy"
        }
    }

    var systemImage: String {
        switch self {
        case .files: return "folder"
        case .git: return "point.bottomleft.forward.to.point.topright.scurvepath"
        case .deploy: return "shippingbox"
        }
    }
}

@MainActor
@Observable
final class RightDockStore {
    static let minWidth: CGFloat = 320
    static let defaultWidth: CGFloat = 420

    private static let keyExpanded = "openowl.rightDock.isExpanded"
    private static let keyActiveTab = "openowl.rightDock.activeTab"
    private static let keyWidth = "openowl.rightDock.width"

    var isExpanded: Bool {
        didSet {
            UserDefaults.standard.set(isExpanded, forKey: Self.keyExpanded)
            if !isExpanded { isFullscreen = false }
        }
    }

    var activeTab: RightDockTab {
        didSet { UserDefaults.standard.set(activeTab.rawValue, forKey: Self.keyActiveTab) }
    }

    var width: CGFloat {
        didSet { UserDefaults.standard.set(Double(width), forKey: Self.keyWidth) }
    }

    /// Fullscreen is session-scoped — not persisted across launches.
    var isFullscreen: Bool = false

    init() {
        let defaults = UserDefaults.standard
        self.isExpanded = defaults.object(forKey: Self.keyExpanded) as? Bool ?? false
        let savedTab = defaults.string(forKey: Self.keyActiveTab) ?? ""
        self.activeTab = RightDockTab(rawValue: savedTab) ?? .git
        let savedWidth = defaults.object(forKey: Self.keyWidth) as? Double
        let resolvedWidth = CGFloat(savedWidth ?? Double(Self.defaultWidth))
        self.width = max(Self.minWidth, resolvedWidth)
    }

    /// Toolbar button behavior:
    /// - panel 折叠 → 展开并切到该 tab
    /// - panel 已展开且 tab 相同 → 折叠
    /// - panel 已展开且 tab 不同 → 切到该 tab（保持展开）
    func toggle(tab: RightDockTab) {
        if !isExpanded {
            activeTab = tab
            isExpanded = true
        } else if activeTab == tab {
            isExpanded = false
        } else {
            activeTab = tab
        }
    }

    func collapse() {
        isExpanded = false
    }

    func expand(tab: RightDockTab) {
        activeTab = tab
        isExpanded = true
    }

    /// No-op when panel is collapsed (no fullscreen without an open panel).
    func toggleFullscreen() {
        guard isExpanded else { return }
        isFullscreen.toggle()
    }

    /// Clamp width to [minWidth, maxWidth]. Caller passes the live maxWidth derived from the host window.
    func setWidth(_ newWidth: CGFloat, maxWidth: CGFloat) {
        let clampedMax = max(Self.minWidth, maxWidth)
        width = min(max(Self.minWidth, newWidth), clampedMax)
    }
}
