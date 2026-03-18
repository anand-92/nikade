import Testing
import Foundation
@testable import openOwl

/// Tests for the silent-failure fixes in FileExplorerStore:
/// - classifyGitState / mergeGitState correctness (used in loadGitStatus)
/// - GitContext.empty is a safe fallback
/// - sortEntries handles empty input
@Suite("FileExplorer Error Handling")
struct FileExplorerErrorHandlingTests {

    // MARK: - GitContext.empty as safe fallback

    @Test func gitContextEmpty_hasNoEntries() {
        let ctx = FileExplorerStore.GitContext.empty
        #expect(ctx.statusByAbsolutePath.isEmpty)
        #expect(ctx.ignoredExactPaths.isEmpty)
        #expect(ctx.ignoredDirectoryPrefixes.isEmpty)
    }

    @Test func isGitIgnored_emptyContext_returnsFalse() {
        // When git status fails and context falls back to .empty,
        // no file should appear gitignored.
        let ctx = FileExplorerStore.GitContext.empty
        #expect(!FileExplorerStore.isGitIgnored(path: "/project/node_modules/foo.js", gitContext: ctx))
        #expect(!FileExplorerStore.isGitIgnored(path: "/project/.build/debug", gitContext: ctx))
    }

    // MARK: - classifyGitState

    @Test func classifyGitState_staged_added() {
        let change = GitFileChange(path: "src/new.swift", indexStatus: "A", workTreeStatus: " ", section: .staged)
        #expect(FileExplorerStore.classifyGitState(for: change) == .added)
    }

    @Test func classifyGitState_unstaged_modified() {
        let change = GitFileChange(path: "src/old.swift", indexStatus: " ", workTreeStatus: "M", section: .modified)
        #expect(FileExplorerStore.classifyGitState(for: change) == .modified)
    }

    @Test func classifyGitState_staged_deleted() {
        let change = GitFileChange(path: "src/gone.swift", indexStatus: "D", workTreeStatus: " ", section: .staged)
        #expect(FileExplorerStore.classifyGitState(for: change) == .deleted)
    }

    @Test func classifyGitState_untracked_mapsToAdded() {
        // "??" from git status (untracked section) maps to .added in the UI
        let change = GitFileChange(path: "src/new.swift", indexStatus: "?", workTreeStatus: "?", section: .untracked)
        #expect(FileExplorerStore.classifyGitState(for: change) == .added)
    }

    @Test func classifyGitState_renamed() {
        let change = GitFileChange(path: "src/new.swift", indexStatus: "R", workTreeStatus: " ", section: .staged)
        #expect(FileExplorerStore.classifyGitState(for: change) == .renamed)
    }

    // MARK: - mergeGitState priority

    @Test func mergeGitState_nilExisting_returnsNew() {
        #expect(FileExplorerStore.mergeGitState(nil, .modified) == .modified)
    }

    @Test func mergeGitState_deleted_winsOver_modified() {
        // deleted has higher priority than modified
        #expect(FileExplorerStore.mergeGitState(.modified, .deleted) == .deleted)
        #expect(FileExplorerStore.mergeGitState(.deleted, .modified) == .deleted)
    }

    @Test func mergeGitState_conflicted_winsOver_deleted() {
        // conflicted has the highest priority
        #expect(FileExplorerStore.mergeGitState(.deleted, .conflicted) == .conflicted)
    }

    // MARK: - sortEntries is safe on empty input

    @Test func sortEntries_emptyInput_returnsEmpty() {
        let result = FileExplorerStore.sortEntries([])
        #expect(result.isEmpty)
    }

    // MARK: - compactDirectoryPrefixes

    @Test func compactDirectoryPrefixes_removesRedundantChildren() {
        // /project/node_modules/foo should be subsumed by /project/node_modules
        let result = FileExplorerStore.compactDirectoryPrefixes([
            "/project/node_modules",
            "/project/node_modules/lodash",
            "/project/.build"
        ])
        #expect(result.contains("/project/node_modules"))
        #expect(result.contains("/project/.build"))
        #expect(!result.contains("/project/node_modules/lodash"))
    }

    @Test func compactDirectoryPrefixes_noOverlap_returnsAll() {
        let input = ["/a/foo", "/b/bar", "/c/baz"]
        let result = FileExplorerStore.compactDirectoryPrefixes(input)
        #expect(Set(result) == Set(input))
    }
}
