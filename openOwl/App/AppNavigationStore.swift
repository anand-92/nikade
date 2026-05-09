import Foundation
import Observation

@MainActor
@Observable
final class AppNavigationStore {
    init() {}

    // MARK: - Unified Navigation API

    /// Open a deployment: activate its project, select it in the deployment panel,
    /// and expand the right dock to the deploy tab.
    func openDeployment(
        id: String,
        deploymentStore: DeploymentStore,
        projectStore: ProjectStore,
        rightDockStore: RightDockStore
    ) {
        if let dep = deploymentStore.deployments.first(where: { $0.id == id }) {
            projectStore.activateProject(id: dep.projectID)
        }
        deploymentStore.selectedDeploymentID = id
        rightDockStore.expand(tab: .deploy)
    }
}
