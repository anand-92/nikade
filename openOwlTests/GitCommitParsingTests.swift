import Testing
import Foundation
@testable import openOwl

@Suite("Git Commit Parsing")
struct GitCommitParsingTests {

    private let service = GitService(workingDirectory: URL(fileURLWithPath: "/tmp"))

    // MARK: - parseCommitFiles

    @Test func parseCommitFiles_mixedStatuses() {
        let output = """
        M\tsrc/main.swift
        A\tsrc/new.swift
        D\tsrc/old.swift
        """
        let files = service.parseCommitFiles(output)
        #expect(files.count == 3)
        #expect(files[0].path == "src/main.swift")
        #expect(files[0].indexStatus == "M")
        #expect(files[1].path == "src/new.swift")
        #expect(files[1].indexStatus == "A")
        #expect(files[2].path == "src/old.swift")
        #expect(files[2].indexStatus == "D")
    }

    @Test func parseCommitFiles_renamed_usesDestinationPath() {
        let output = "R100\told.swift\tnew.swift"
        let files = service.parseCommitFiles(output)
        #expect(files.count == 1)
        #expect(files[0].indexStatus == "R")
        #expect(files[0].path == "new.swift")  // destination, not source
    }

    @Test func parseCommitFiles_copied_usesDestinationPath() {
        let output = "C100\toriginal.swift\tcopy.swift"
        let files = service.parseCommitFiles(output)
        #expect(files.count == 1)
        #expect(files[0].indexStatus == "C")
        #expect(files[0].path == "copy.swift")
    }

    @Test func parseCommitFiles_renamed_quotedPaths() {
        let output = "R100\t\"old dir/a.swift\"\t\"new dir/b.swift\""
        let files = service.parseCommitFiles(output)
        #expect(files.count == 1)
        #expect(files[0].indexStatus == "R")
        #expect(files[0].path == "new dir/b.swift")
    }

    @Test func parseCommitFiles_empty() {
        let files = service.parseCommitFiles("")
        #expect(files.isEmpty)
    }

    @Test func parseCommitFiles_allStaged() {
        let output = "A\tfile.swift"
        let files = service.parseCommitFiles(output)
        #expect(files[0].section == .staged)
        #expect(files[0].workTreeStatus == " ")
    }

    @Test func parseCommitFiles_quotedPath() {
        let output = "M\t\"path with spaces/file.swift\""
        let files = service.parseCommitFiles(output)
        #expect(files.count == 1)
        #expect(files[0].path == "path with spaces/file.swift")
    }

    // MARK: - parseBranch edge cases

    @Test func parseBranch_aheadOnly() {
        let result = service.parseBranch(from: "## main...origin/main [ahead 2]")
        #expect(result.trackingSummary == "ahead 2")
    }

    @Test func parseBranch_emptyPayload() {
        let result = service.parseBranch(from: "## ")
        #expect(result.branch == "HEAD")
    }

    // MARK: - parseStatus edge cases

    @Test func parseStatus_stagedAndModified() throws {
        // File both staged and modified (MM)
        let output = """
        ## main
        MM file.swift
        """
        let snapshot = try service.parseStatus(output)
        #expect(snapshot.staged.count == 1)
        #expect(snapshot.modified.count == 1)
        #expect(snapshot.staged[0].path == "file.swift")
        #expect(snapshot.modified[0].path == "file.swift")
    }

    @Test func parseStatus_copiedFile() throws {
        let output = """
        ## main
        C  original.swift -> copy.swift
        """
        let snapshot = try service.parseStatus(output)
        #expect(snapshot.staged.count == 1)
        #expect(snapshot.staged[0].path == "copy.swift")
    }

    @Test func parseStatus_multipleUntracked() throws {
        let output = """
        ## main
        ?? a.txt
        ?? b.txt
        ?? c.txt
        """
        let snapshot = try service.parseStatus(output)
        #expect(snapshot.untracked.count == 3)
    }
}
