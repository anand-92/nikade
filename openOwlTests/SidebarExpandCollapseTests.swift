import Testing
import Foundation
@testable import openOwl

@Suite("Sidebar Expand/Collapse")
struct SidebarExpandCollapseTests {

    // MARK: - Default state: all projects expanded

    @Test @MainActor func allProjects_expandedByDefault() {
        let store = ProjectStore()
        let id = "test-project-id"
        #expect(store.isExpanded(id) == true)
    }

    // MARK: - toggleExpanded

    @Test @MainActor func toggleExpanded_collapsesExpandedProject() {
        let store = ProjectStore()
        let id = "proj-1"

        store.toggleExpanded(id)

        #expect(store.isExpanded(id) == false)
    }

    @Test @MainActor func toggleExpanded_reExpandsCollapsedProject() {
        let store = ProjectStore()
        let id = "proj-1"

        store.toggleExpanded(id)  // collapse
        store.toggleExpanded(id)  // re-expand

        #expect(store.isExpanded(id) == true)
    }

    @Test @MainActor func toggleExpanded_independentPerProject() {
        let store = ProjectStore()

        store.toggleExpanded("a")
        store.toggleExpanded("b")
        store.toggleExpanded("b")  // re-expand b

        #expect(store.isExpanded("a") == false)
        #expect(store.isExpanded("b") == true)
        #expect(store.isExpanded("c") == true)  // never toggled → expanded
    }

    // MARK: - collapsedProjectIDs persistence across toggles

    @Test @MainActor func collapsedProjectIDs_tracksState() {
        let store = ProjectStore()

        store.toggleExpanded("x")
        #expect(store.collapsedProjectIDs.contains("x"))

        store.toggleExpanded("x")
        #expect(!store.collapsedProjectIDs.contains("x"))
    }

    // MARK: - Branch row fallback text

    @Test func projectItem_lastBranch_nilFallback() {
        let item = ProjectItem(url: URL(fileURLWithPath: "/tmp/project"))
        #expect(item.lastBranch == nil)
        // Sidebar uses: project.lastBranch ?? "No commits yet"
        let display = item.lastBranch ?? "No commits yet"
        #expect(display == "No commits yet")
    }

    @Test func projectItem_lastBranch_showsBranchWhenSet() {
        var item = ProjectItem(url: URL(fileURLWithPath: "/tmp/project"))
        item.lastBranch = "main"
        #expect(item.lastBranch == "main")
    }
}
