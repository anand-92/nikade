import Foundation

enum GitChangeSection: String, CaseIterable, Hashable {
    case staged = "Staged Changes"
    case modified = "Changes"
    case untracked = "Untracked"
}

struct GitFileChange: Identifiable, Hashable {
    let path: String
    let indexStatus: Character
    let workTreeStatus: Character
    let section: GitChangeSection

    var id: String {
        "\(section.rawValue)::\(path)::\(indexStatus)\(workTreeStatus)"
    }

    var statusCode: String {
        "\(indexStatus)\(workTreeStatus)"
    }
}

struct GitStatusSnapshot {
    let repositoryRoot: URL
    let branch: String
    let upstreamBranch: String?
    let branchTrackingStatus: String?
    let aheadCount: Int
    let behindCount: Int
    let staged: [GitFileChange]
    let modified: [GitFileChange]
    let untracked: [GitFileChange]

    var hasStagedChanges: Bool { !staged.isEmpty }
    var hasAnyChanges: Bool { hasStagedChanges || !modified.isEmpty || !untracked.isEmpty }
}

enum GitServiceError: LocalizedError {
    case notGitRepository
    case commandFailed(command: String, exitCode: Int32, stderr: String)
    case invalidCommitMessage

    var errorDescription: String? {
        switch self {
        case .notGitRepository:
            return "Selected directory is not a Git repository."
        case .commandFailed(let command, let exitCode, let stderr):
            let details = stderr.isEmpty ? "Unknown git error" : stderr
            return "`\(command)` failed (\(exitCode)): \(details)"
        case .invalidCommitMessage:
            return "Commit message cannot be empty."
        }
    }
}

final class GitService {
    let workingDirectory: URL

    init(workingDirectory: URL) {
        self.workingDirectory = workingDirectory
    }

    func repositoryRoot() async throws -> URL {
        let root = try await runGit(["rev-parse", "--show-toplevel"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !root.isEmpty else {
            throw GitServiceError.notGitRepository
        }
        return URL(fileURLWithPath: root, isDirectory: true)
    }

    func status() async throws -> GitStatusSnapshot {
        let output = try await runGit(["status", "--porcelain=v1", "--branch"])
        return try parseStatus(output)
    }

    func stage(files: [String]) async throws {
        guard !files.isEmpty else { return }
        _ = try await runGit(["add", "--"] + files)
    }

    func stageAll() async throws {
        _ = try await runGit(["add", "-A"])
    }

    func unstage(files: [String]) async throws {
        guard !files.isEmpty else { return }
        _ = try await runGit(["restore", "--staged", "--"] + files)
    }

    func unstageAll() async throws {
        _ = try await runGit(["restore", "--staged", ":/"])
    }

    func discardModified(files: [String]) async throws {
        guard !files.isEmpty else { return }
        _ = try await runGit(["restore", "--worktree", "--"] + files)
    }

    func discardUntracked(paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        _ = try await runGit(["clean", "-f", "-d", "--"] + paths)
    }

    func commit(message: String, autoStageWhenNeeded: Bool) async throws {
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw GitServiceError.invalidCommitMessage
        }

        if autoStageWhenNeeded {
            try await stageAll()
        }

        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("openowl-commit-\(UUID().uuidString).txt")

        try normalized.write(to: fileURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        _ = try await runGit(["commit", "--file", fileURL.path])
    }

    func diff(for change: GitFileChange) async throws -> String {
        switch change.section {
        case .staged:
            return try await runGit(["diff", "--staged", "--", change.path])

        case .modified:
            return try await runGit(["diff", "--", change.path])

        case .untracked:
            return try await runGit(["diff", "--no-index", "--", "/dev/null", change.path], allowFailure: true)
        }
    }

    func branches() async throws -> [String] {
        let output = try await runGit(["for-each-ref", "--format=%(refname:short)", "refs/heads"])
        return output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty }
            .sorted()
    }

    func checkout(branch: String) async throws {
        let trimmed = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = try await runGit(["checkout", trimmed])
    }

    func createBranch(name: String, checkout: Bool = true) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if checkout {
            _ = try await runGit(["switch", "-c", trimmed])
        } else {
            _ = try await runGit(["branch", trimmed])
        }
    }

    func deleteBranch(name: String, force: Bool = false) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = try await runGit(["branch", force ? "-D" : "-d", trimmed])
    }

    func fetch() async throws {
        _ = try await runGit(["fetch", "--all", "--prune"])
    }

    func pull() async throws {
        _ = try await runGit(["pull", "--rebase", "--autostash"])
    }

    func push() async throws {
        _ = try await runGit(["push"])
    }

    func ignoredPaths() async throws -> [String] {
        let output = try await runGit(["ls-files", "-z", "--others", "--ignored", "--exclude-standard", "--directory"])
        return output
            .split(separator: "\0")
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private extension GitService {
    func parseStatus(_ output: String) throws -> GitStatusSnapshot {
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        var branch = "HEAD"
        var upstreamBranch: String?
        var branchStatus: String?
        var aheadCount = 0
        var behindCount = 0

        var staged: [GitFileChange] = []
        var modified: [GitFileChange] = []
        var untracked: [GitFileChange] = []

        for line in lines {
            if line.hasPrefix("## ") {
                let parsed = parseBranch(from: line)
                branch = parsed.branch
                upstreamBranch = parsed.upstreamBranch
                branchStatus = parsed.trackingSummary
                let counts = parseAheadBehind(from: parsed.trackingSummary)
                aheadCount = counts.ahead
                behindCount = counts.behind
                continue
            }

            if line.hasPrefix("?? ") {
                let rawPath = String(line.dropFirst(3))
                let path = decodePath(rawPath)
                untracked.append(
                    GitFileChange(path: path, indexStatus: "?", workTreeStatus: "?", section: .untracked)
                )
                continue
            }

            guard line.count >= 3 else { continue }

            let x = line[line.startIndex]
            let y = line[line.index(after: line.startIndex)]
            let rawPath = String(line.dropFirst(3))
            let path = decodePath(parsePath(rawPath))

            if x != " " {
                staged.append(
                    GitFileChange(path: path, indexStatus: x, workTreeStatus: y, section: .staged)
                )
            }

            if y != " " {
                modified.append(
                    GitFileChange(path: path, indexStatus: x, workTreeStatus: y, section: .modified)
                )
            }
        }

        let root = workingDirectory.standardizedFileURL
        return GitStatusSnapshot(
            repositoryRoot: root,
            branch: branch,
            upstreamBranch: upstreamBranch,
            branchTrackingStatus: branchStatus,
            aheadCount: aheadCount,
            behindCount: behindCount,
            staged: staged.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending },
            modified: modified.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending },
            untracked: untracked.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        )
    }

    func parseBranch(from line: String) -> (branch: String, upstreamBranch: String?, trackingSummary: String?) {
        let payload = line.replacingOccurrences(of: "## ", with: "")
        if let dotsRange = payload.range(of: "...") {
            let name = String(payload[..<dotsRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let trackingPayload = String(payload[dotsRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

            if let bracketStart = trackingPayload.firstIndex(of: "["),
               let bracketEnd = trackingPayload.lastIndex(of: "]"),
               bracketStart < bracketEnd {
                let upstream = String(trackingPayload[..<bracketStart]).trimmingCharacters(in: .whitespacesAndNewlines)
                let summary = String(trackingPayload[trackingPayload.index(after: bracketStart)..<bracketEnd])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return (
                    branch: name.isEmpty ? "HEAD" : name,
                    upstreamBranch: upstream.isEmpty ? nil : upstream,
                    trackingSummary: summary.isEmpty ? nil : summary
                )
            }

            return (
                branch: name.isEmpty ? "HEAD" : name,
                upstreamBranch: trackingPayload.isEmpty ? nil : trackingPayload,
                trackingSummary: nil
            )
        }

        return (branch: payload.isEmpty ? "HEAD" : payload, upstreamBranch: nil, trackingSummary: nil)
    }

    func parseAheadBehind(from trackingSummary: String?) -> (ahead: Int, behind: Int) {
        guard let trackingSummary else { return (0, 0) }
        var ahead = 0
        var behind = 0

        let segments = trackingSummary.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }

        for segment in segments {
            if segment.hasPrefix("ahead ") {
                let number = segment.dropFirst("ahead ".count).trimmingCharacters(in: .whitespacesAndNewlines)
                ahead = Int(number) ?? 0
            } else if segment.hasPrefix("behind ") {
                let number = segment.dropFirst("behind ".count).trimmingCharacters(in: .whitespacesAndNewlines)
                behind = Int(number) ?? 0
            }
        }

        return (ahead, behind)
    }

    func parsePath(_ rawPath: String) -> String {
        if let arrowRange = rawPath.range(of: " -> ") {
            return String(rawPath[arrowRange.upperBound...])
        }
        return rawPath
    }

    func decodePath(_ rawPath: String) -> String {
        guard rawPath.count >= 2, rawPath.first == "\"", rawPath.last == "\"" else {
            return rawPath
        }

        let body = rawPath.dropFirst().dropLast()
        var output = ""
        var iterator = body.makeIterator()

        while let char = iterator.next() {
            if char != "\\" {
                output.append(char)
                continue
            }

            guard let escaped = iterator.next() else {
                output.append("\\")
                break
            }

            switch escaped {
            case "\\": output.append("\\")
            case "\"": output.append("\"")
            case "n": output.append("\n")
            case "t": output.append("\t")
            case "r": output.append("\r")
            default:
                output.append(escaped)
            }
        }

        return output
    }

    func runGit(_ arguments: [String], allowFailure: Bool = false) async throws -> String {
        let workingDirectory = self.workingDirectory
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["git"] + arguments
                process.currentDirectoryURL = workingDirectory

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

                    if process.terminationStatus == 0 || allowFailure {
                        continuation.resume(returning: stdout)
                        return
                    }

                    let command = (["git"] + arguments).joined(separator: " ")
                    if stderr.contains("not a git repository") {
                        continuation.resume(throwing: GitServiceError.notGitRepository)
                        return
                    }

                    continuation.resume(
                        throwing: GitServiceError.commandFailed(
                            command: command,
                            exitCode: process.terminationStatus,
                            stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
