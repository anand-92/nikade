import Testing
import Foundation
@testable import openOwl

@Suite("FileExplorer Parsing")
struct FileExplorerParsingTests {

    // MARK: - classifyGitState

    @Test func classifyGitState_added() {
        let change = GitFileChange(path: "new.swift", indexStatus: "A", workTreeStatus: " ", section: .staged)
        #expect(FileExplorerStore.classifyGitState(for: change) == .added)
    }

    @Test func classifyGitState_modified() {
        let change = GitFileChange(path: "file.swift", indexStatus: "M", workTreeStatus: " ", section: .staged)
        #expect(FileExplorerStore.classifyGitState(for: change) == .modified)
    }

    @Test func classifyGitState_deleted() {
        let change = GitFileChange(path: "old.swift", indexStatus: "D", workTreeStatus: " ", section: .staged)
        #expect(FileExplorerStore.classifyGitState(for: change) == .deleted)
    }

    @Test func classifyGitState_renamed() {
        let change = GitFileChange(path: "new.swift", indexStatus: "R", workTreeStatus: " ", section: .staged)
        #expect(FileExplorerStore.classifyGitState(for: change) == .renamed)
    }

    @Test func classifyGitState_conflict_U() {
        let change = GitFileChange(path: "file.swift", indexStatus: "U", workTreeStatus: "U", section: .modified)
        #expect(FileExplorerStore.classifyGitState(for: change) == .conflicted)
    }

    @Test func classifyGitState_conflict_AA() {
        let change = GitFileChange(path: "file.swift", indexStatus: "A", workTreeStatus: "A", section: .modified)
        #expect(FileExplorerStore.classifyGitState(for: change) == .conflicted)
    }

    @Test func classifyGitState_untracked() {
        let change = GitFileChange(path: "file.txt", indexStatus: "?", workTreeStatus: "?", section: .untracked)
        #expect(FileExplorerStore.classifyGitState(for: change) == .added)
    }

    @Test func classifyGitState_typeChange() {
        let change = GitFileChange(path: "file", indexStatus: "T", workTreeStatus: " ", section: .staged)
        #expect(FileExplorerStore.classifyGitState(for: change) == .modified)
    }

    // MARK: - isConflict

    @Test func isConflict_U_flag() {
        #expect(FileExplorerStore.isConflict(indexStatus: "U", workTreeStatus: " ") == true)
        #expect(FileExplorerStore.isConflict(indexStatus: " ", workTreeStatus: "U") == true)
    }

    @Test func isConflict_AA() {
        #expect(FileExplorerStore.isConflict(indexStatus: "A", workTreeStatus: "A") == true)
    }

    @Test func isConflict_DD() {
        #expect(FileExplorerStore.isConflict(indexStatus: "D", workTreeStatus: "D") == true)
    }

    @Test func isConflict_normalChange() {
        #expect(FileExplorerStore.isConflict(indexStatus: "M", workTreeStatus: " ") == false)
        #expect(FileExplorerStore.isConflict(indexStatus: "A", workTreeStatus: " ") == false)
    }

    // MARK: - mergeGitState

    @Test func mergeGitState_nilLHS() {
        #expect(FileExplorerStore.mergeGitState(nil, .added) == .added)
    }

    @Test func mergeGitState_nilRHS() {
        #expect(FileExplorerStore.mergeGitState(.modified, nil) == .modified)
    }

    @Test func mergeGitState_higherPriorityWins() {
        #expect(FileExplorerStore.mergeGitState(.added, .conflicted) == .conflicted)
        #expect(FileExplorerStore.mergeGitState(.deleted, .modified) == .deleted)
    }

    @Test func mergeGitState_bothNil() {
        #expect(FileExplorerStore.mergeGitState(nil, nil) == nil)
    }

    // MARK: - compactDirectoryPrefixes

    @Test func compactDirectoryPrefixes_removesSubpaths() {
        let input = ["/a/b/c", "/a/b", "/d/e"]
        let result = FileExplorerStore.compactDirectoryPrefixes(input)
        #expect(result.contains("/a/b"))
        #expect(result.contains("/d/e"))
        #expect(!result.contains("/a/b/c"))
    }

    @Test func compactDirectoryPrefixes_deduplicates() {
        let input = ["/a/b", "/a/b", "/a/b"]
        let result = FileExplorerStore.compactDirectoryPrefixes(input)
        #expect(result.count == 1)
        #expect(result.first == "/a/b")
    }

    @Test func compactDirectoryPrefixes_empty() {
        #expect(FileExplorerStore.compactDirectoryPrefixes([]).isEmpty)
    }

    @Test func compactDirectoryPrefixes_noOverlap() {
        let input = ["/a", "/b", "/c"]
        let result = FileExplorerStore.compactDirectoryPrefixes(input)
        #expect(result.count == 3)
    }

    // MARK: - fuzzyMatch

    @Test func fuzzyMatch_exactName() {
        let result = FileExplorerStore.fuzzyMatch(name: "main.swift", path: "src/main.swift", query: "main.swift")
        #expect(result != nil)
        #expect(result!.score > 1000) // exact match bonus
    }

    @Test func fuzzyMatch_prefix() {
        let result = FileExplorerStore.fuzzyMatch(name: "ContentView.swift", path: "src/ContentView.swift", query: "content")
        #expect(result != nil)
        #expect(result!.score > 500) // prefix bonus
    }

    @Test func fuzzyMatch_fuzzyCharacters() {
        let result = FileExplorerStore.fuzzyMatch(name: "GitService.swift", path: "openOwl/Services/GitService.swift", query: "gs")
        #expect(result != nil)
    }

    @Test func fuzzyMatch_noMatch() {
        let result = FileExplorerStore.fuzzyMatch(name: "main.swift", path: "src/main.swift", query: "xyz")
        #expect(result == nil)
    }

    @Test func fuzzyMatch_emptyQuery() {
        let result = FileExplorerStore.fuzzyMatch(name: "file.swift", path: "file.swift", query: "")
        #expect(result != nil)
        #expect(result!.score == 0)
    }

    @Test func fuzzyMatch_pathFallback() {
        // Query doesn't match filename but matches path
        let result = FileExplorerStore.fuzzyMatch(name: "index.ts", path: "src/components/index.ts", query: "components")
        #expect(result != nil)
    }

    @Test func fuzzyMatch_deeperPathScoresLower() {
        let shallow = FileExplorerStore.fuzzyMatch(name: "file.swift", path: "src/file.swift", query: "file")
        let deep = FileExplorerStore.fuzzyMatch(name: "file.swift", path: "a/b/c/d/e/file.swift", query: "file")
        #expect(shallow != nil)
        #expect(deep != nil)
        #expect(shallow!.score > deep!.score)
    }

    // MARK: - shouldIgnore

    @Test func shouldIgnore_gitDirectory() {
        let url = URL(fileURLWithPath: "/project/.git")
        #expect(FileExplorerStore.shouldIgnore(url: url, gitContext: .empty) == true)
    }

    @Test func shouldIgnore_dsStore() {
        let url = URL(fileURLWithPath: "/project/.DS_Store")
        #expect(FileExplorerStore.shouldIgnore(url: url, gitContext: .empty) == true)
    }

    @Test func shouldIgnore_normalFile() {
        let url = URL(fileURLWithPath: "/project/main.swift")
        #expect(FileExplorerStore.shouldIgnore(url: url, gitContext: .empty) == false)
    }

    @Test func shouldIgnore_derivedData() {
        let url = URL(fileURLWithPath: "/project/DerivedData")
        #expect(FileExplorerStore.shouldIgnore(url: url, gitContext: .empty) == true)
    }

    // MARK: - Lazy directory scan boundaries

    @Test func scanProject_defersGeneratedDependencyDirectories() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("node_modules/lodash"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("src"),
            withIntermediateDirectories: true
        )
        try "module".write(
            to: root.appendingPathComponent("node_modules/lodash/index.js"),
            atomically: true,
            encoding: .utf8
        )
        try "print(\"ok\")".write(
            to: root.appendingPathComponent("src/main.swift"),
            atomically: true,
            encoding: .utf8
        )

        let result = FileExplorerStore.scanProject(projectURL: root, gitContext: .empty)
        let nodeModulesPath = root.appendingPathComponent("node_modules").standardizedFileURL.path
        let nestedPackagePath = root.appendingPathComponent("node_modules/lodash/index.js").standardizedFileURL.path
        let sourcePath = root.appendingPathComponent("src/main.swift").standardizedFileURL.path

        #expect(result.index[nodeModulesPath]?.children == nil)
        #expect(result.index[nestedPackagePath] == nil)
        #expect(result.index[sourcePath] != nil)
    }

    @Test func scanProject_defersNestedGitRepositories() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let nestedRepo = root.appendingPathComponent("projects/app")
        try FileManager.default.createDirectory(
            at: nestedRepo.appendingPathComponent("src"),
            withIntermediateDirectories: true
        )
        try "gitdir: ../.git/worktrees/app".write(
            to: nestedRepo.appendingPathComponent(".git"),
            atomically: true,
            encoding: .utf8
        )
        try "print(\"nested\")".write(
            to: nestedRepo.appendingPathComponent("src/main.swift"),
            atomically: true,
            encoding: .utf8
        )

        let result = FileExplorerStore.scanProject(projectURL: root, gitContext: .empty)
        let nestedRepoPath = nestedRepo.standardizedFileURL.path
        let nestedSourcePath = nestedRepo.appendingPathComponent("src/main.swift").standardizedFileURL.path

        #expect(result.index[nestedRepoPath]?.children == nil)
        #expect(result.index[nestedSourcePath] == nil)
    }

    @Test func scanProject_scansOpenedGitRepositoryRoot() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("src"),
            withIntermediateDirectories: true
        )
        try "print(\"root\")".write(
            to: root.appendingPathComponent("src/main.swift"),
            atomically: true,
            encoding: .utf8
        )

        let result = FileExplorerStore.scanProject(projectURL: root, gitContext: .empty)
        let sourcePath = root.appendingPathComponent("src/main.swift").standardizedFileURL.path

        #expect(result.index[sourcePath] != nil)
    }

    // MARK: - isGitIgnored

    @Test func isGitIgnored_exactPath() {
        let ctx = FileExplorerStore.GitContext(
            statusByAbsolutePath: [:],
            ignoredExactPaths: ["/project/secret.key"],
            ignoredDirectoryPrefixes: []
        )
        #expect(FileExplorerStore.isGitIgnored(path: "/project/secret.key", gitContext: ctx) == true)
        #expect(FileExplorerStore.isGitIgnored(path: "/project/other.key", gitContext: ctx) == false)
    }

    @Test func isGitIgnored_directoryPrefix() {
        let ctx = FileExplorerStore.GitContext(
            statusByAbsolutePath: [:],
            ignoredExactPaths: [],
            ignoredDirectoryPrefixes: ["/project/node_modules"]
        )
        #expect(FileExplorerStore.isGitIgnored(path: "/project/node_modules", gitContext: ctx) == true)
        #expect(FileExplorerStore.isGitIgnored(path: "/project/node_modules/lodash/index.js", gitContext: ctx) == true)
        #expect(FileExplorerStore.isGitIgnored(path: "/project/src/app.js", gitContext: ctx) == false)
    }

    // MARK: - displayName

    @Test func displayName_normal() {
        let url = URL(fileURLWithPath: "/Users/dev/project/main.swift")
        #expect(FileExplorerStore.displayName(for: url) == "main.swift")
    }

    @Test func displayName_root() {
        let url = URL(fileURLWithPath: "/")
        #expect(FileExplorerStore.displayName(for: url) == "/")
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("openowl-file-explorer-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

// MARK: - FileGitState

@Suite("FileGitState")
struct FileGitStateTests {

    @Test func priority_ordering() {
        #expect(FileGitState.conflicted.priority > FileGitState.deleted.priority)
        #expect(FileGitState.deleted.priority > FileGitState.renamed.priority)
        #expect(FileGitState.renamed.priority > FileGitState.modified.priority)
        #expect(FileGitState.modified.priority > FileGitState.added.priority)
    }

    @Test func shortCode_values() {
        #expect(FileGitState.added.shortCode == "A")
        #expect(FileGitState.modified.shortCode == "M")
        #expect(FileGitState.deleted.shortCode == "D")
        #expect(FileGitState.renamed.shortCode == "R")
        #expect(FileGitState.conflicted.shortCode == "U")
    }
}
