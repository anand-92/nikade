import Foundation
import Observation

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
            return "Git"
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
@Observable
final class AppNavigationStore {
    var activeTab: ViewTab {
        didSet { UserDefaults.standard.set(activeTab.rawValue, forKey: "activeTab") }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: "activeTab") ?? ""
        self.activeTab = ViewTab(rawValue: saved) ?? .terminal
    }

    // MARK: - Unified Navigation API

    func navigate(to tab: ViewTab) {
        activeTab = tab
    }

    func openDeployment(id: String, deploymentStore: DeploymentStore, projectStore: ProjectStore) {
        if let dep = deploymentStore.deployments.first(where: { $0.id == id }) {
            projectStore.activateProject(id: dep.projectID)
        }
        deploymentStore.selectedDeploymentID = id
        activeTab = .deployments
    }
}
