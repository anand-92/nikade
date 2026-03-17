import Testing
import Foundation
@testable import openOwl

@Suite("AppNavigationStore")
struct AppNavigationStoreTests {

    // MARK: - navigate(to:)

    @Test @MainActor func navigate_switchesActiveTab() {
        let store = AppNavigationStore()
        store.navigate(to: .gitChanges)
        #expect(store.activeTab == .gitChanges)

        store.navigate(to: .fileExplorer)
        #expect(store.activeTab == .fileExplorer)

        store.navigate(to: .terminal)
        #expect(store.activeTab == .terminal)

        store.navigate(to: .deployments)
        #expect(store.activeTab == .deployments)
    }

    @Test @MainActor func navigate_persistsToUserDefaults() {
        let store = AppNavigationStore()
        store.navigate(to: .gitChanges)

        let saved = UserDefaults.standard.string(forKey: "activeTab")
        #expect(saved == ViewTab.gitChanges.rawValue)

        // Clean up
        UserDefaults.standard.removeObject(forKey: "activeTab")
    }

    @Test @MainActor func navigate_sameTab_noError() {
        let store = AppNavigationStore()
        store.navigate(to: .terminal)
        store.navigate(to: .terminal) // should not crash
        #expect(store.activeTab == .terminal)
    }

    // MARK: - openDeployment(id:...)

    @Test @MainActor func openDeployment_switchesToDeploymentsTab() {
        let navStore = AppNavigationStore()
        let deployStore = DeploymentStore()
        let projStore = ProjectStore()

        navStore.navigate(to: .terminal)
        navStore.openDeployment(id: "nonexistent", deploymentStore: deployStore, projectStore: projStore)

        #expect(navStore.activeTab == .deployments)
    }

    @Test @MainActor func openDeployment_setsSelectedID() {
        let navStore = AppNavigationStore()
        let deployStore = DeploymentStore()
        let projStore = ProjectStore()

        navStore.openDeployment(id: "deploy-123", deploymentStore: deployStore, projectStore: projStore)

        #expect(deployStore.selectedDeploymentID == "deploy-123")
    }

    // MARK: - init restores from UserDefaults

    @Test @MainActor func init_restoresSavedTab() {
        UserDefaults.standard.set(ViewTab.fileExplorer.rawValue, forKey: "activeTab")
        let store = AppNavigationStore()
        #expect(store.activeTab == .fileExplorer)

        // Clean up
        UserDefaults.standard.removeObject(forKey: "activeTab")
    }

    @Test @MainActor func init_defaultsToTerminal_whenNoSavedValue() {
        UserDefaults.standard.removeObject(forKey: "activeTab")
        let store = AppNavigationStore()
        #expect(store.activeTab == .terminal)
    }

    @Test @MainActor func init_defaultsToTerminal_whenInvalidSavedValue() {
        UserDefaults.standard.set("invalid_tab", forKey: "activeTab")
        let store = AppNavigationStore()
        #expect(store.activeTab == .terminal)

        // Clean up
        UserDefaults.standard.removeObject(forKey: "activeTab")
    }
}
