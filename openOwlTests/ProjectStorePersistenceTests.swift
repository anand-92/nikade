import Testing
import Foundation
@testable import openOwl

@Suite("ProjectStore Persistence")
struct ProjectStorePersistenceTests {

    // MARK: - ProjectItem Codable

    @Test func projectItem_roundTrip() throws {
        let item = ProjectItem(
            path: "/Users/dev/project",
            name: "project",
            worktreeOf: "parent-123",
            worktreeBranch: "feature/x"
        )

        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ProjectItem.self, from: data)

        #expect(decoded.name == "project")
        #expect(decoded.worktreeOf == "parent-123")
        #expect(decoded.worktreeBranch == "feature/x")
        #expect(decoded.isWorktree == true)
    }

    @Test func projectItem_minimalJSON() throws {
        // Old JSON without optional fields
        let json = """
        {"id": "abc", "path": "/tmp/p", "name": "p"}
        """
        let decoded = try JSONDecoder().decode(ProjectItem.self, from: Data(json.utf8))
        #expect(decoded.id == "abc")
        #expect(decoded.worktreeOf == nil)
        #expect(decoded.worktreeBranch == nil)
        #expect(decoded.lastBranch == nil)
        #expect(decoded.branchPrefix == nil)
        #expect(decoded.isWorktree == false)
    }

    @Test func projectItem_withBranchPrefix() throws {
        let json = """
        {"id": "x", "path": "/tmp/p", "name": "p", "branchPrefix": "sanvi"}
        """
        let decoded = try JSONDecoder().decode(ProjectItem.self, from: Data(json.utf8))
        #expect(decoded.branchPrefix == "sanvi")
    }

    // MARK: - ProjectItem identity

    @Test func projectItem_pathNormalization() {
        let item1 = ProjectItem(url: URL(fileURLWithPath: "/Users/dev/project/"))
        let item2 = ProjectItem(url: URL(fileURLWithPath: "/Users/dev/project"))
        #expect(item1.path == item2.path)
    }

    @Test func projectItem_displayName_fromPath() {
        let item = ProjectItem(url: URL(fileURLWithPath: "/Users/dev/my-project"))
        #expect(item.displayName == "my-project")
    }

    // MARK: - openowl.json format

    @Test func storeFileFormat_matchesExpected() throws {
        // Simulate what ProjectStore writes
        let items = [
            ProjectItem(url: URL(fileURLWithPath: "/tmp/project1")),
            ProjectItem(url: URL(fileURLWithPath: "/tmp/project2")),
        ]

        struct StoreFile: Codable {
            var projects: [ProjectItem]
            var activeProjectId: String?
        }

        let store = StoreFile(projects: items, activeProjectId: items[0].id)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(store)
        let json = String(data: data, encoding: .utf8)!

        #expect(json.contains("\"projects\""))
        #expect(json.contains("\"activeProjectId\""))
        #expect(json.contains(items[0].id))

        // Verify round-trip
        let decoded = try JSONDecoder().decode(StoreFile.self, from: data)
        #expect(decoded.projects.count == 2)
        #expect(decoded.activeProjectId == items[0].id)
    }
}
