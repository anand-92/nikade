import Combine
import Foundation

enum ViewTab: String, CaseIterable, Hashable, Identifiable {
    case fileExplorer
    case gitChanges
    case terminal
    case deployments

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terminal:
            return "Terminal"
        case .gitChanges:
            return "Git Changes"
        case .fileExplorer:
            return "Files"
        case .deployments:
            return "Deploy"
        }
    }

    var systemImage: String {
        switch self {
        case .terminal: return "terminal"
        case .gitChanges: return "point.bottomleft.forward.to.point.topright.scurvepath"
        case .fileExplorer: return "folder"
        case .deployments: return "shippingbox"
        }
    }
}

@MainActor
final class AppNavigationStore: ObservableObject {
    @Published var activeTab: ViewTab = .terminal
}
