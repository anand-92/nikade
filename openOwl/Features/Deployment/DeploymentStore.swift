import Foundation
import Observation
import SwiftUI

// MARK: - Model

enum DeploymentStatus: String, Codable {
    case stopped
    case building
    case running
    case error

    var color: Color {
        switch self {
        case .running: return AppColors.success
        case .error: return AppColors.error
        case .building: return AppColors.warning
        case .stopped: return .gray
        }
    }

    var displayLabel: String {
        switch self {
        case .running: return "Running"
        case .building: return "Building\u{2026}"
        case .error: return "Error"
        case .stopped: return "Stopped"
        }
    }
}

struct Deployment: Identifiable, Codable, Hashable {
    let id: String
    let projectID: String
    var name: String
    var isRemote: Bool = false          // true = pure health-check monitor, no local process
    var branch: String
    var installCommand: String?
    var buildCommand: String?
    var startCommand: String?
    var envVars: String?
    var port: Int?
    var healthCheckURL: String?
    var status: DeploymentStatus
    var pid: Int32?
    var clonePath: String
    var remoteURL: String
    var lastCommit: String?
    var createdAt: Date
    var lastStartedAt: Date?

    // Memberwise init (needed because custom init(from:) disables the synthesized one)
    init(
        id: String, projectID: String, name: String, isRemote: Bool = false,
        branch: String, installCommand: String? = nil, buildCommand: String? = nil,
        startCommand: String? = nil, envVars: String? = nil, port: Int? = nil,
        healthCheckURL: String? = nil, status: DeploymentStatus, pid: Int32? = nil,
        clonePath: String = "", remoteURL: String = "", lastCommit: String? = nil,
        createdAt: Date = Date(), lastStartedAt: Date? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.name = name
        self.isRemote = isRemote
        self.branch = branch
        self.installCommand = installCommand
        self.buildCommand = buildCommand
        self.startCommand = startCommand
        self.envVars = envVars
        self.port = port
        self.healthCheckURL = healthCheckURL
        self.status = status
        self.pid = pid
        self.clonePath = clonePath
        self.remoteURL = remoteURL
        self.lastCommit = lastCommit
        self.createdAt = createdAt
        self.lastStartedAt = lastStartedAt
    }

    var cloneURL: URL { URL(fileURLWithPath: clonePath, isDirectory: true) }

    var logFileURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let safeName = name.replacingOccurrences(of: " ", with: "-").lowercased()
        return home.appendingPathComponent(".openowl/deployments/\(safeName)/logs/current.log")
    }

    // Backward-compatible decoding: new fields fall back to defaults when missing in old JSON
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        projectID = try c.decode(String.self, forKey: .projectID)
        name = try c.decode(String.self, forKey: .name)
        isRemote = try c.decodeIfPresent(Bool.self, forKey: .isRemote) ?? false
        branch = try c.decodeIfPresent(String.self, forKey: .branch) ?? ""
        installCommand = try c.decodeIfPresent(String.self, forKey: .installCommand)
        buildCommand = try c.decodeIfPresent(String.self, forKey: .buildCommand)
        startCommand = try c.decodeIfPresent(String.self, forKey: .startCommand)
        envVars = try c.decodeIfPresent(String.self, forKey: .envVars)
        port = try c.decodeIfPresent(Int.self, forKey: .port)
        healthCheckURL = try c.decodeIfPresent(String.self, forKey: .healthCheckURL)
        status = try c.decode(DeploymentStatus.self, forKey: .status)
        pid = try c.decodeIfPresent(Int32.self, forKey: .pid)
        clonePath = try c.decodeIfPresent(String.self, forKey: .clonePath) ?? ""
        remoteURL = try c.decodeIfPresent(String.self, forKey: .remoteURL) ?? ""
        lastCommit = try c.decodeIfPresent(String.self, forKey: .lastCommit)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        lastStartedAt = try c.decodeIfPresent(Date.self, forKey: .lastStartedAt)
    }
}

// MARK: - Store

@MainActor
@Observable
final class DeploymentStore {
    private(set) var deployments: [Deployment] = []
    var selectedDeploymentID: String?
    private(set) var logContent: String = ""
    private(set) var healthStatus: [String: Bool] = [:]  // id → healthy
    private(set) var healthError: [String: String] = [:] // id → error message
    private(set) var healthLastChecked: [String: Date] = [:] // id → timestamp

    private let processManager = DeploymentProcessManager()
    private let defaults = UserDefaults.standard
    private let storeKey = "openowl.deployments.store"
    private var pollTimers: [String: Timer] = [:]
    private var logPollTimer: Timer?
    private var logPollURL: URL?
    private var logLastSize: UInt64 = 0
    var logBuffer = ""
    private var logFlushTimer: Timer?
    var activeStreamIDs = Set<String>()

    init() {
        load()
    }

    // MARK: - Queries

    func deployments(for projectID: String) -> [Deployment] {
        deployments.filter { $0.projectID == projectID }
    }

    func hasRunningDeployments() -> Bool {
        deployments.contains { $0.status == .running || $0.status == .building }
    }

    // MARK: - Create

    func createDeployment(
        projectID: String,
        name: String,
        branch: String,
        installCommand: String?,
        buildCommand: String?,
        startCommand: String?,
        envVars: String?,
        port: Int?,
        healthCheckURL: String?,
        remoteURL: String
    ) async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let safeName = name.replacingOccurrences(of: " ", with: "-").lowercased()
        let clonePath = home.appendingPathComponent(".openowl/deployments/\(safeName)/repo")

        let deployment = Deployment(
            id: UUID().uuidString,
            projectID: projectID,
            name: name,
            branch: branch,
            installCommand: installCommand.nilIfEmpty,
            buildCommand: buildCommand.nilIfEmpty,
            startCommand: startCommand.nilIfEmpty,
            envVars: envVars.nilIfEmpty,
            port: port,
            healthCheckURL: healthCheckURL.nilIfEmpty,
            status: .building,
            clonePath: clonePath.path,
            remoteURL: remoteURL,
            createdAt: Date()
        )

        deployments.append(deployment)
        selectedDeploymentID = deployment.id
        persist()

        do {
            // Clone
            try await cloneRepo(remoteURL: remoteURL, branch: branch, to: clonePath)
            updateDeployment(id: deployment.id) { $0.status = .building }

            // Install (if command provided)
            if let installCmd = deployment.installCommand, !installCmd.isEmpty {
                try await runBuild(id: deployment.id, command: installCmd, workDir: clonePath, envVars: deployment.envVars)
            }

            // Build (if command provided)
            if let buildCmd = deployment.buildCommand, !buildCmd.isEmpty {
                try await runBuild(id: deployment.id, command: buildCmd, workDir: clonePath, envVars: deployment.envVars)
            }

            // Start (if command provided)
            if let startCmd = deployment.startCommand, !startCmd.isEmpty {
                try startProcess(id: deployment.id)
            } else {
                updateDeployment(id: deployment.id) { $0.status = .stopped }
            }

            // Start branch poll
            startBranchPoll(id: deployment.id)
        } catch {
            updateDeployment(id: deployment.id) { $0.status = .error }
            throw error
        }
    }

    // MARK: - Create Remote Monitor

    func createRemoteMonitor(
        projectID: String,
        name: String,
        healthCheckURL: String
    ) {
        let deployment = Deployment(
            id: UUID().uuidString,
            projectID: projectID,
            name: name,
            isRemote: true,
            branch: "",
            healthCheckURL: healthCheckURL,
            status: .running,
            clonePath: "",
            remoteURL: "",
            createdAt: Date()
        )

        deployments.append(deployment)
        selectedDeploymentID = deployment.id
        persist()

        // Start health polling
        startBranchPoll(id: deployment.id)

        // Run first check immediately
        Task { await checkHealth(dep: deployment) }
    }

    // MARK: - Save

    func updateDeployment(
        id: String,
        name: String,
        branch: String,
        installCommand: String?,
        buildCommand: String?,
        startCommand: String?,
        envVars: String?,
        port: Int?,
        healthCheckURL: String?
    ) {
        guard let index = deployments.firstIndex(where: { $0.id == id }) else { return }
        deployments[index].name = name
        deployments[index].branch = branch
        deployments[index].installCommand = installCommand.nilIfEmpty
        deployments[index].buildCommand = buildCommand.nilIfEmpty
        deployments[index].startCommand = startCommand.nilIfEmpty
        deployments[index].envVars = envVars.nilIfEmpty
        deployments[index].port = port
        deployments[index].healthCheckURL = healthCheckURL.nilIfEmpty
        persist()
    }

    // MARK: - Lifecycle

    func start(id: String) async throws {
        guard let index = deployments.firstIndex(where: { $0.id == id }) else { return }
        let dep = deployments[index]

        updateDeployment(id: id) { $0.status = .building }

        do {
            // Install if needed
            if let installCmd = dep.installCommand, !installCmd.isEmpty {
                try await runBuild(id: id, command: installCmd, workDir: dep.cloneURL, envVars: dep.envVars)
            }

            // Build if needed
            if let buildCmd = dep.buildCommand, !buildCmd.isEmpty {
                try await runBuild(id: id, command: buildCmd, workDir: dep.cloneURL, envVars: dep.envVars)
            }

            // Start if command provided
            if let startCmd = dep.startCommand, !startCmd.isEmpty {
                try startProcess(id: id)
            } else {
                updateDeployment(id: id) { $0.status = .stopped }
            }
            startBranchPoll(id: id)
        } catch {
            updateDeployment(id: id) { $0.status = .error }
            throw error
        }
    }

    func stop(id: String) async {
        processManager.terminate(id: id)
        activeStreamIDs.remove(id)
        updateDeployment(id: id) {
            $0.status = .stopped
            $0.pid = nil
        }
        stopBranchPoll(id: id)
    }

    func restart(id: String) async throws {
        await stop(id: id)
        try? await Task.sleep(for: .seconds(1))
        try await start(id: id)
    }

    func removeDeployment(id: String) async {
        await stop(id: id)

        if let dep = deployments.first(where: { $0.id == id }) {
            // Clean up clone directory
            let deployDir = dep.cloneURL.deletingLastPathComponent()
            try? FileManager.default.removeItem(at: deployDir)
        }

        deployments.removeAll { $0.id == id }
        if selectedDeploymentID == id {
            selectedDeploymentID = deployments.first?.id
        }
        persist()
    }

    // MARK: - Recovery

    func recoverRunningDeployments() {
        for i in deployments.indices {
            // Remote monitors: resume polling + immediate check
            if deployments[i].isRemote {
                startBranchPoll(id: deployments[i].id)
                let dep = deployments[i]
                Task { await checkHealth(dep: dep) }
                continue
            }

            if deployments[i].status == .running || deployments[i].status == .building {
                if let pid = deployments[i].pid, DeploymentProcessManager.isProcessAlive(pid: pid) {
                    startBranchPoll(id: deployments[i].id)
                } else {
                    deployments[i].status = .error
                    deployments[i].pid = nil
                }
            }
        }
        persist()
    }

    // MARK: - Logs

    func loadLog(for id: String) {
        stopLogPoll()

        guard let dep = deployments.first(where: { $0.id == id }) else {
            logContent = ""
            return
        }

        let logURL = dep.logFileURL
        logPollURL = logURL
        logLastSize = 0

        // Read existing content
        readFullLog(logURL)

        // Only poll the file when there's no active real-time stream
        // (real-time onOutput already pushes updates directly)
        guard !activeStreamIDs.contains(id) else { return }

        // Poll for new content every 0.5s
        logPollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollLogFile()
            }
        }
    }

    // MARK: - Private: Process

    private func startProcess(id: String) throws {
        guard let index = deployments.firstIndex(where: { $0.id == id }) else { return }
        let dep = deployments[index]
        guard let command = dep.startCommand, !command.isEmpty else { return }

        var env: [String: String] = [:]
        if let raw = dep.envVars, !raw.isEmpty {
            env = DeploymentProcessManager.parseEnvString(raw)
        }
        if let port = dep.port {
            env["PORT"] = "\(port)"
        }

        activeStreamIDs.insert(id)

        let pid = try processManager.launch(
            id: id,
            command: command,
            workDir: dep.cloneURL,
            env: env,
            logFile: dep.logFileURL,
            onOutput: { [weak self] text in
                guard let self, self.selectedDeploymentID == id else { return }
                self.appendLog(text)
            }
        ) { [weak self] exitCode in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.activeStreamIDs.remove(id)
                let newStatus: DeploymentStatus = exitCode == 0 ? .stopped : .error
                self.updateDeployment(id: id) {
                    $0.status = newStatus
                    $0.pid = nil
                }
                self.stopBranchPoll(id: id)
            }
        }

        updateDeployment(id: id) {
            $0.pid = pid
            $0.status = .running
            $0.lastStartedAt = Date()
        }
    }

    // MARK: - Private: Git Operations

    private func cloneRepo(remoteURL: String, branch: String, to destination: URL) async throws {
        // Remove existing directory if present
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        let parentDir = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["git", "clone", "--branch", branch, "--single-branch", remoteURL, destination.path]

                let stderrPipe = Pipe()
                process.standardError = stderrPipe
                process.standardOutput = Pipe()

                do {
                    try process.run()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()

                    if process.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        let stderr = String(data: stderrData, encoding: .utf8) ?? "Unknown error"
                        continuation.resume(throwing: DeploymentError.cloneFailed(stderr))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runBuild(id: String, command: String, workDir: URL, envVars: String?) async throws {
        let logFile: URL? = deployments.first(where: { $0.id == id })?.logFileURL
        if let logFile {
            let logDir = logFile.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: logFile.path) {
                FileManager.default.createFile(atPath: logFile.path, contents: nil)
            }
        }

        var env: [String: String] = [:]
        if let raw = envVars, !raw.isEmpty {
            env = DeploymentProcessManager.parseEnvString(raw)
        }

        // Capture self weakly for real-time streaming
        let selectedID = selectedDeploymentID
        let streamToUI: (String) -> Void = { [weak self] text in
            DispatchQueue.main.async {
                guard let self, selectedID == id else { return }
                self.appendLog(text)
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-l", "-c", command]
                process.currentDirectoryURL = workDir

                var mergedEnv = ProcessInfo.processInfo.environment
                for (key, value) in env { mergedEnv[key] = value }
                process.environment = mergedEnv

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                let logHandle = logFile.flatMap { try? FileHandle(forWritingTo: $0) }
                logHandle?.seekToEndOfFile()

                let marker = "[\(DeploymentProcessManager.timestamp())] Running: \(command)\n"
                if let data = marker.data(using: .utf8) { logHandle?.write(data) }
                streamToUI(marker)

                stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else {
                        handle.readabilityHandler = nil
                        return
                    }
                    logHandle?.write(data)
                    if let text = String(data: data, encoding: .utf8) {
                        streamToUI(text)
                    }
                }
                stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else {
                        handle.readabilityHandler = nil
                        return
                    }
                    logHandle?.write(data)
                    if let text = String(data: data, encoding: .utf8) {
                        streamToUI(text)
                    }
                }

                do {
                    try process.run()
                    process.waitUntilExit()

                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    try? logHandle?.close()

                    if process.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: DeploymentError.buildFailed(command))
                    }
                } catch {
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    try? logHandle?.close()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Private: Branch Polling

    private func startBranchPoll(id: String) {
        stopBranchPoll(id: id)

        let timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkForUpdates(id: id)
            }
        }
        pollTimers[id] = timer
    }

    private func stopBranchPoll(id: String) {
        pollTimers[id]?.invalidate()
        pollTimers.removeValue(forKey: id)
    }

    private func checkForUpdates(id: String) async {
        guard let dep = deployments.first(where: { $0.id == id }) else { return }

        // Remote monitors: only health check, no git
        if dep.isRemote {
            await checkHealth(dep: dep)
            return
        }

        guard dep.status == .running else { return }

        let git = GitService(workingDirectory: dep.cloneURL)
        do {
            let oldCommit = dep.lastCommit

            try await git.fetch()
            try await git.pull()

            // Check if HEAD changed after pull
            let headOutput = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                DispatchQueue.global(qos: .utility).async {
                    let proc = Process()
                    proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                    proc.arguments = ["git", "rev-parse", "HEAD"]
                    proc.currentDirectoryURL = dep.cloneURL
                    let pipe = Pipe()
                    proc.standardOutput = pipe
                    proc.standardError = Pipe()
                    do {
                        try proc.run()
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        proc.waitUntilExit()
                        continuation.resume(returning: String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

            updateDeployment(id: id) { $0.lastCommit = headOutput }
            if headOutput != oldCommit, oldCommit != nil {
                try await restart(id: id)
            }
        } catch {
            NSLog("Deployment poll failed for %@: %@", dep.name, error.localizedDescription)
        }

        // Health check
        await checkHealth(dep: dep)
    }

    // MARK: - Private: Health Check

    private static let healthSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private func checkHealth(dep: Deployment) async {
        guard let urlString = dep.healthCheckURL, !urlString.isEmpty,
              let url = URL(string: urlString) else {
            healthStatus.removeValue(forKey: dep.id)
            healthError.removeValue(forKey: dep.id)
            return
        }

        NSLog("Health check: %@ → %@", dep.name, urlString)

        do {
            let (_, response) = try await Self.healthSession.data(from: url)
            healthLastChecked[dep.id] = Date()
            if let http = response as? HTTPURLResponse {
                let ok = (200...299).contains(http.statusCode)
                healthStatus[dep.id] = ok
                healthError[dep.id] = ok ? nil : "HTTP \(http.statusCode)"
                NSLog("Health check: %@ → %d", dep.name, http.statusCode)
            } else {
                healthStatus[dep.id] = false
                healthError[dep.id] = "Invalid response"
            }
        } catch {
            healthLastChecked[dep.id] = Date()
            healthStatus[dep.id] = false
            healthError[dep.id] = error.localizedDescription
            NSLog("Health check failed: %@ → %@", dep.name, error.localizedDescription)
        }
    }

    // MARK: - Private: Log Polling

    private func readFullLog(_ logURL: URL) {
        guard FileManager.default.fileExists(atPath: logURL.path),
              let data = try? Data(contentsOf: logURL) else {
            logContent = ""
            logLastSize = 0
            return
        }
        let trimmed = data.count > 50_000 ? data.suffix(50_000) : data
        logContent = String(data: trimmed, encoding: .utf8) ?? ""
        logLastSize = UInt64(data.count)
    }

    private func pollLogFile() {
        guard let logURL = logPollURL else { return }

        guard FileManager.default.fileExists(atPath: logURL.path) else {
            // File doesn't exist yet — will pick it up next poll
            return
        }

        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logURL.path),
              let fileSize = attrs[.size] as? UInt64 else { return }

        if logLastSize == 0 && fileSize > 0 {
            // First time seeing content — read it all
            readFullLog(logURL)
            return
        }

        guard fileSize > logLastSize else { return }

        // Read only new bytes
        guard let handle = try? FileHandle(forReadingFrom: logURL) else { return }
        handle.seek(toFileOffset: logLastSize)
        let newData = handle.readDataToEndOfFile()
        try? handle.close()

        logLastSize = fileSize

        if let text = String(data: newData, encoding: .utf8), !text.isEmpty {
            logContent.append(text)
            // Cap at ~100KB in memory
            if logContent.count > 100_000 {
                logContent = String(logContent.suffix(80_000))
            }
        }
    }

    private func stopLogPoll() {
        logPollTimer?.invalidate()
        logPollTimer = nil
        logPollURL = nil
        logLastSize = 0
        flushLogBuffer()
    }

    // MARK: - Log Append (real-time)

    func appendLog(_ text: String) {
        logBuffer.append(text)
        guard logFlushTimer == nil else { return }
        logFlushTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.flushLogBuffer()
            }
        }
    }

    func flushLogBuffer() {
        logFlushTimer?.invalidate()
        logFlushTimer = nil
        guard !logBuffer.isEmpty else { return }
        logContent.append(logBuffer)
        logBuffer = ""
        if logContent.count > 100_000 {
            logContent = String(logContent.suffix(80_000))
        }
    }

    // MARK: - Private: State Helpers

    private func updateDeployment(id: String, _ mutate: (inout Deployment) -> Void) {
        guard let index = deployments.firstIndex(where: { $0.id == id }) else {
            NSLog("openOwl: [DeploymentStore] updateDeployment called with unknown id=%@", id)
            return
        }
        mutate(&deployments[index])
        persist()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: storeKey) else { return }
        do {
            deployments = try JSONDecoder().decode([Deployment].self, from: data)
        } catch {
            NSLog("openOwl: [DeploymentStore] Failed to decode deployments: %@", error.localizedDescription)
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(deployments)
            defaults.set(data, forKey: storeKey)
        } catch {
            NSLog("openOwl: [DeploymentStore] Failed to encode deployments: %@", error.localizedDescription)
        }
    }
}

// MARK: - Errors

enum DeploymentError: LocalizedError {
    case cloneFailed(String)
    case buildFailed(String)
    case startFailed(String)

    var errorDescription: String? {
        switch self {
        case .cloneFailed(let detail): return "Clone failed: \(detail)"
        case .buildFailed(let cmd): return "Build failed: \(cmd)"
        case .startFailed(let detail): return "Start failed: \(detail)"
        }
    }
}

// MARK: - Helpers

extension Optional where Wrapped == String {
    /// Returns nil if the string is nil or empty; otherwise returns the string.
    var nilIfEmpty: String? {
        guard let self, !self.isEmpty else { return nil }
        return self
    }
}
