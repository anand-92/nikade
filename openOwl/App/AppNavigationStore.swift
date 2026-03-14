import Combine
import Foundation

enum ViewTab: String, CaseIterable, Hashable, Identifiable {
    case fileExplorer
    case gitChanges
    case terminal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terminal:
            return "Terminal"
        case .gitChanges:
            return "Git Changes"
        case .fileExplorer:
            return "Files"
        }
    }

    var systemImage: String {
        switch self {
        case .terminal: return "terminal"
        case .gitChanges: return "point.bottomleft.forward.to.point.topright.scurvepath"
        case .fileExplorer: return "folder"
        }
    }
}

@MainActor
final class AppNavigationStore: ObservableObject {
    @Published var activeTab: ViewTab = .terminal
}
