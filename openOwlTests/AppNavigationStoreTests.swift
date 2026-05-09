import Testing
import Foundation
@testable import openOwl

@Suite("AppNavigationStore")
struct AppNavigationStoreTests {
    private static func clearDockDefaults() {
        UserDefaults.standard.removeObject(forKey: "openowl.rightDock.isExpanded")
        UserDefaults.standard.removeObject(forKey: "openowl.rightDock.activeTab")
        UserDefaults.standard.removeObject(forKey: "openowl.rightDock.width")
    }

    // MARK: - openDeployment(id:...)

    @Test @MainActor func openDeployment_setsSelectedID() {
        Self.clearDockDefaults()
        let navStore = AppNavigationStore()
        let deployStore = DeploymentStore()
        let projStore = ProjectStore()
        let dockStore = RightDockStore()

        navStore.openDeployment(
            id: "deploy-123",
            deploymentStore: deployStore,
            projectStore: projStore,
            rightDockStore: dockStore
        )

        #expect(deployStore.selectedDeploymentID == "deploy-123")
        Self.clearDockDefaults()
    }

    @Test @MainActor func openDeployment_expandsRightDockToDeployTab() {
        Self.clearDockDefaults()
        let navStore = AppNavigationStore()
        let deployStore = DeploymentStore()
        let projStore = ProjectStore()
        let dockStore = RightDockStore()
        #expect(dockStore.isExpanded == false)

        navStore.openDeployment(
            id: "deploy-123",
            deploymentStore: deployStore,
            projectStore: projStore,
            rightDockStore: dockStore
        )

        #expect(dockStore.isExpanded == true)
        #expect(dockStore.activeTab == .deploy)
        Self.clearDockDefaults()
    }

    @Test @MainActor func openDeployment_existingDeployment_setsSelectedAndOpensTab() {
        Self.clearDockDefaults()
        let navStore = AppNavigationStore()
        let deployStore = DeploymentStore()
        let projStore = ProjectStore()
        let dockStore = RightDockStore()

        let dep = Deployment(
            id: "deploy-1", projectID: "proj-A", name: "test",
            branch: "main", status: .stopped
        )
        deployStore.deployments.append(dep)

        navStore.openDeployment(
            id: "deploy-1",
            deploymentStore: deployStore,
            projectStore: projStore,
            rightDockStore: dockStore
        )

        #expect(deployStore.selectedDeploymentID == "deploy-1")
        #expect(dockStore.activeTab == .deploy)
        #expect(dockStore.isExpanded == true)
        Self.clearDockDefaults()
    }

    @Test @MainActor func openDeployment_unknownDeployment_stillSetsSelected() {
        Self.clearDockDefaults()
        let navStore = AppNavigationStore()
        let deployStore = DeploymentStore()
        let projStore = ProjectStore()
        let dockStore = RightDockStore()

        navStore.openDeployment(
            id: "missing-id",
            deploymentStore: deployStore,
            projectStore: projStore,
            rightDockStore: dockStore
        )

        // Even when no matching deployment exists, the tray-menu flow still expects
        // the deploy tab to surface so the user can see the (empty) selection.
        #expect(deployStore.selectedDeploymentID == "missing-id")
        #expect(dockStore.activeTab == .deploy)
        #expect(dockStore.isExpanded == true)
        Self.clearDockDefaults()
    }
}
