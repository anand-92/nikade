import Testing
import Foundation
@testable import openOwl

@Suite("FileExplorer Git Propagation")
struct FileExplorerGitPropagationTests {

    // MARK: - mergeGitState symmetry

    @Test func mergeGitState_symmetric() {
        let result1 = FileExplorerStore.mergeGitState(.added, .deleted)
        let result2 = FileExplorerStore.mergeGitState(.deleted, .added)
        #expect(result1 == result2)
        #expect(result1 == .deleted) // higher priority wins
    }

    @Test func mergeGitState_sameState() {
        #expect(FileExplorerStore.mergeGitState(.modified, .modified) == .modified)
    }

    // MARK: - isGitIgnored with multiple prefixes

    @Test func isGitIgnored_nestedPrefixes() {
        let ctx = FileExplorerStore.GitContext(
            statusByAbsolutePath: [:],
            ignoredExactPaths: [],
            ignoredDirectoryPrefixes: ["/project/node_modules", "/project/.build"]
        )
        #expect(FileExplorerStore.isGitIgnored(path: "/project/node_modules/lodash/index.js", gitContext: ctx))
        #expect(FileExplorerStore.isGitIgnored(path: "/project/.build/debug/app", gitContext: ctx))
        #expect(!FileExplorerStore.isGitIgnored(path: "/project/src/main.swift", gitContext: ctx))
    }

    @Test func isGitIgnored_exactAndPrefix_combined() {
        let ctx = FileExplorerStore.GitContext(
            statusByAbsolutePath: [:],
            ignoredExactPaths: ["/project/secret.env"],
            ignoredDirectoryPrefixes: ["/project/vendor"]
        )
        #expect(FileExplorerStore.isGitIgnored(path: "/project/secret.env", gitContext: ctx))
        #expect(FileExplorerStore.isGitIgnored(path: "/project/vendor/lib/foo.js", gitContext: ctx))
        #expect(!FileExplorerStore.isGitIgnored(path: "/project/src/app.swift", gitContext: ctx))
    }

    // MARK: - compactDirectoryPrefixes edge cases

    @Test func compactDirectoryPrefixes_nestedThreeLevels() {
        let input = ["/a/b/c/d", "/a/b/c", "/a/b", "/a"]
        let result = FileExplorerStore.compactDirectoryPrefixes(input)
        #expect(result == ["/a"])
    }

    @Test func compactDirectoryPrefixes_similarButNotNested() {
        // "/a/bc" is NOT a subpath of "/a/b"
        let input = ["/a/b", "/a/bc"]
        let result = FileExplorerStore.compactDirectoryPrefixes(input)
        #expect(result.count == 2)
    }

    // MARK: - shouldIgnore

    @Test func shouldIgnore_ghosttyResources() {
        let url = URL(fileURLWithPath: "/project/ghostty-resources")
        #expect(FileExplorerStore.shouldIgnore(url: url, gitContext: .empty))
    }

    @Test func shouldIgnore_xcframework() {
        let url = URL(fileURLWithPath: "/project/GhosttyKit.xcframework")
        #expect(FileExplorerStore.shouldIgnore(url: url, gitContext: .empty))
    }

    @Test func shouldIgnore_buildDir() {
        let url = URL(fileURLWithPath: "/project/.build")
        #expect(FileExplorerStore.shouldIgnore(url: url, gitContext: .empty))
    }

    @Test func shouldIgnore_normalDir_notIgnored() {
        let url = URL(fileURLWithPath: "/project/Sources")
        #expect(!FileExplorerStore.shouldIgnore(url: url, gitContext: .empty))
    }

    // MARK: - classifyGitState edge cases

    @Test func classifyGitState_copyStatus() {
        let change = GitFileChange(path: "copy.swift", indexStatus: "C", workTreeStatus: " ", section: .staged)
        #expect(FileExplorerStore.classifyGitState(for: change) == .renamed)
    }

    @Test func classifyGitState_conflict_DD() {
        let change = GitFileChange(path: "file.swift", indexStatus: "D", workTreeStatus: "D", section: .modified)
        #expect(FileExplorerStore.classifyGitState(for: change) == .conflicted)
    }

    @Test func classifyGitState_workTreeModified() {
        let change = GitFileChange(path: "file.swift", indexStatus: " ", workTreeStatus: "M", section: .modified)
        #expect(FileExplorerStore.classifyGitState(for: change) == .modified)
    }

    // MARK: - displayName edge cases

    @Test func displayName_hiddenFile() {
        let url = URL(fileURLWithPath: "/project/.gitignore")
        #expect(FileExplorerStore.displayName(for: url) == ".gitignore")
    }

    @Test func displayName_deepPath() {
        let url = URL(fileURLWithPath: "/a/b/c/d/e/file.txt")
        #expect(FileExplorerStore.displayName(for: url) == "file.txt")
    }
}
