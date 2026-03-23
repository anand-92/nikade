import Testing
import Foundation
@testable import openOwl

@Suite("Deployment Recovery & Safety")
struct DeploymentRecoveryTests {

    // MARK: - Batch Recovery

    @Test @MainActor func recoverRunningDeployments_deadProcess_marksError() {
        let store = DeploymentStore()

        // Manually inject a deployment that claims to be running with a bogus PID
        let dep = Deployment(
            id: "d1", projectID: "p1", name: "test-service",
            branch: "main", startCommand: "npm start",
            status: .running, pid: 99999,
            clonePath: "/tmp/fake", remoteURL: "https://example.com/repo"
        )
        store.deployments.append(dep)

        store.recoverRunningDeployments()

        let recovered = store.deployments.first(where: { $0.id == "d1" })
        #expect(recovered?.status == .error)
        #expect(recovered?.pid == nil)
    }

    @Test @MainActor func recoverRunningDeployments_stoppedDeployment_unchanged() {
        let store = DeploymentStore()

        let dep = Deployment(
            id: "d2", projectID: "p1", name: "stopped-service",
            branch: "main", status: .stopped,
            clonePath: "/tmp/fake", remoteURL: "https://example.com/repo"
        )
        store.deployments.append(dep)

        store.recoverRunningDeployments()

        let recovered = store.deployments.first(where: { $0.id == "d2" })
        #expect(recovered?.status == .stopped)
    }

    @Test @MainActor func recoverRunningDeployments_errorDeployment_unchanged() {
        let store = DeploymentStore()

        let dep = Deployment(
            id: "d3", projectID: "p1", name: "error-service",
            branch: "main", status: .error,
            clonePath: "/tmp/fake", remoteURL: "https://example.com/repo"
        )
        store.deployments.append(dep)

        store.recoverRunningDeployments()

        let recovered = store.deployments.first(where: { $0.id == "d3" })
        #expect(recovered?.status == .error)
    }

    @Test @MainActor func recoverRunningDeployments_multipleDeadProcesses_batchUpdate() {
        let store = DeploymentStore()

        for i in 0..<5 {
            let dep = Deployment(
                id: "d\(i)", projectID: "p1", name: "svc-\(i)",
                branch: "main", status: .running, pid: Int32(99990 + i),
                clonePath: "/tmp/fake-\(i)", remoteURL: "https://example.com/repo"
            )
            store.deployments.append(dep)
        }

        store.recoverRunningDeployments()

        // All should be marked error since PIDs don't exist
        for i in 0..<5 {
            let d = store.deployments.first(where: { $0.id == "d\(i)" })
            #expect(d?.status == .error, "deployment d\(i) should be .error")
            #expect(d?.pid == nil, "deployment d\(i) pid should be nil")
        }
    }

    // MARK: - Path Safety

    @Test func isSafeDeploymentPath_validPath_returnsTrue() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let safe = home.appendingPathComponent(".openowl/deployments/my-app")
        #expect(DeploymentStore.isSafeDeploymentPath(safe) == true)
    }

    @Test func isSafeDeploymentPath_deploymentsRoot_returnsFalse() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let root = home.appendingPathComponent(".openowl/deployments")
        #expect(DeploymentStore.isSafeDeploymentPath(root) == false)
    }

    @Test func isSafeDeploymentPath_homeDirectory_returnsFalse() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(DeploymentStore.isSafeDeploymentPath(home) == false)
    }

    @Test func isSafeDeploymentPath_rootDirectory_returnsFalse() {
        let root = URL(fileURLWithPath: "/")
        #expect(DeploymentStore.isSafeDeploymentPath(root) == false)
    }

    @Test func isSafeDeploymentPath_userProjectDirectory_returnsFalse() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let project = home.appendingPathComponent("Documents/workspace/my-project")
        #expect(DeploymentStore.isSafeDeploymentPath(project) == false)
    }

    @Test func isSafeDeploymentPath_nestedDeployPath_returnsTrue() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let nested = home.appendingPathComponent(".openowl/deployments/my-app/repo")
        #expect(DeploymentStore.isSafeDeploymentPath(nested) == true)
    }

    @Test func isSafeDeploymentPath_siblingDirectoryName_returnsFalse() {
        // "deployments-evil" starts with "deployments" but is NOT a child
        let home = FileManager.default.homeDirectoryForCurrentUser
        let evil = home.appendingPathComponent(".openowl/deployments-evil/payload")
        #expect(DeploymentStore.isSafeDeploymentPath(evil) == false)
    }
}
