import Combine
import Foundation

enum SidebarSelection: String, CaseIterable, Hashable, Identifiable {
    case terminal
    case gitChanges
    case fileExplorer

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
}

@MainActor
final class AppNavigationStore: ObservableObject {
    @Published var selection: SidebarSelection? = .terminal
}
