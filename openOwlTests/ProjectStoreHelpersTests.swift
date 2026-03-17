import Testing
import Foundation
@testable import openOwl

@Suite("ProjectStore Helpers")
struct ProjectStoreHelpersTests {

    // MARK: - DeploymentStatus

    @Test func deploymentStatus_displayLabel() {
        #expect(DeploymentStatus.running.displayLabel == "Running")
        #expect(DeploymentStatus.building.displayLabel == "Building\u{2026}")
        #expect(DeploymentStatus.error.displayLabel == "Error")
        #expect(DeploymentStatus.stopped.displayLabel == "Stopped")
    }

    @Test func deploymentStatus_codable() throws {
        for status in [DeploymentStatus.running, .building, .error, .stopped] {
            let data = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(DeploymentStatus.self, from: data)
            #expect(decoded == status)
        }
    }

    // MARK: - Deployment computed properties

    @Test func deployment_logFileURL() {
        let d = Deployment(
            id: "1", projectID: "p1", name: "My Service",
            branch: "main", status: .stopped
        )
        let path = d.logFileURL.path
        #expect(path.contains(".openowl/deployments/my-service/logs/current.log"))
    }

    @Test func deployment_cloneURL() {
        let d = Deployment(
            id: "1", projectID: "p1", name: "Test",
            branch: "main", status: .stopped, clonePath: "/tmp/clone"
        )
        #expect(d.cloneURL.path == "/tmp/clone")
    }

    // MARK: - ProjectItem

    @Test func projectItem_urlFromPath() {
        let item = ProjectItem(url: URL(fileURLWithPath: "/Users/dev/project"))
        #expect(item.url.path == "/Users/dev/project")
        #expect(item.displayName == "project")
    }

    @Test func projectItem_isWorktree() {
        var item = ProjectItem(
            path: "/tmp/wt",
            name: "feature",
            worktreeOf: "parent-id",
            worktreeBranch: "feature/x"
        )
        #expect(item.isWorktree == true)

        item = ProjectItem(url: URL(fileURLWithPath: "/tmp/project"))
        #expect(item.isWorktree == false)
    }

    // MARK: - GitServiceError

    @Test func gitServiceError_descriptions() {
        let notGit = GitServiceError.notGitRepository
        #expect(notGit.errorDescription?.contains("not a Git repository") == true)

        let failed = GitServiceError.commandFailed(command: "git push", exitCode: 1, stderr: "rejected")
        #expect(failed.errorDescription?.contains("git push") == true)
        #expect(failed.errorDescription?.contains("rejected") == true)

        let invalid = GitServiceError.invalidCommitMessage
        #expect(invalid.errorDescription?.contains("empty") == true)
    }

    @Test func gitServiceError_emptyStderr() {
        let err = GitServiceError.commandFailed(command: "git pull", exitCode: 128, stderr: "")
        #expect(err.errorDescription?.contains("Unknown git error") == true)
    }

    // MARK: - GitFileChange

    @Test func gitFileChange_id_uniquePerSection() {
        let staged = GitFileChange(path: "file.swift", indexStatus: "M", workTreeStatus: " ", section: .staged)
        let modified = GitFileChange(path: "file.swift", indexStatus: " ", workTreeStatus: "M", section: .modified)
        #expect(staged.id != modified.id)
    }

    @Test func gitFileChange_statusCode() {
        let change = GitFileChange(path: "file.swift", indexStatus: "A", workTreeStatus: "M", section: .staged)
        #expect(change.statusCode == "AM")
    }

    // MARK: - GitStatusSnapshot

    @Test func gitStatusSnapshot_hasAnyChanges() {
        let empty = GitStatusSnapshot(
            repositoryRoot: URL(fileURLWithPath: "/tmp"),
            branch: "main", upstreamBranch: nil, branchTrackingStatus: nil,
            aheadCount: 0, behindCount: 0,
            staged: [], modified: [], untracked: [], untrackedTruncated: false
        )
        #expect(empty.hasAnyChanges == false)
        #expect(empty.hasStagedChanges == false)

        let withStaged = GitStatusSnapshot(
            repositoryRoot: URL(fileURLWithPath: "/tmp"),
            branch: "main", upstreamBranch: nil, branchTrackingStatus: nil,
            aheadCount: 0, behindCount: 0,
            staged: [GitFileChange(path: "a", indexStatus: "A", workTreeStatus: " ", section: .staged)],
            modified: [], untracked: [], untrackedTruncated: false
        )
        #expect(withStaged.hasAnyChanges == true)
        #expect(withStaged.hasStagedChanges == true)
    }
}
