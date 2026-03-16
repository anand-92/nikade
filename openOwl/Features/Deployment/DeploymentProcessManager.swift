import Foundation

final class DeploymentProcessManager {
    private var processes: [String: Process] = [:]
    private let queue = DispatchQueue(label: "com.openowl.deployment.process", attributes: .concurrent)

    /// Launch a deployment process. Returns the PID.
    /// `onOutput` is called on main thread with each chunk of stdout/stderr — for real-time UI.
    func launch(
        id: String,
        command: String,
        workDir: URL,
        env: [String: String],
        logFile: URL,
        onOutput: @escaping (String) -> Void,
        onExit: @escaping (Int32) -> Void
    ) throws -> Int32 {
        // Ensure log directory exists
        let logDir = logFile.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

        // Create/truncate log file
        FileManager.default.createFile(atPath: logFile.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logFile)
        logHandle.seekToEndOfFile()

        let process = Process()
        // Use login shell so user PATH (nvm, volta, homebrew, etc.) is available
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", command]
        process.currentDirectoryURL = workDir
        process.environment = Self.mergedEnvironment(extra: env)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Stream stdout → log file + real-time UI callback
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            logHandle.write(data)
            if let text = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async { onOutput(text) }
            }
        }

        // Stream stderr → log file + real-time UI callback
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            logHandle.write(data)
            if let text = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async { onOutput(text) }
            }
        }

        process.terminationHandler = { [weak self] proc in
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            try? logHandle.close()

            self?.queue.async(flags: .barrier) {
                self?.processes.removeValue(forKey: id)
            }

            let status = proc.terminationStatus
            DispatchQueue.main.async {
                onExit(status)
            }
        }

        try process.run()
        let pid = process.processIdentifier

        queue.async(flags: .barrier) {
            self.processes[id] = process
        }

        // Write startup marker to log + UI
        let marker = "[\(Self.timestamp())] Process started (PID: \(pid), command: \(command))\n"
        if let data = marker.data(using: .utf8) {
            logHandle.write(data)
        }
        DispatchQueue.main.async { onOutput(marker) }

        return pid
    }

    /// Graceful terminate: SIGTERM → 5s wait → SIGKILL if still alive
    func terminate(id: String) {
        var process: Process?
        queue.sync {
            process = processes[id]
        }
        guard let proc = process, proc.isRunning else { return }

        proc.terminate() // SIGTERM

        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            if proc.isRunning {
                kill(proc.processIdentifier, SIGKILL)
            }
        }
    }

    func terminateAll() {
        var allProcesses: [String: Process] = [:]
        queue.sync { allProcesses = processes }
        for (id, _) in allProcesses {
            terminate(id: id)
        }
    }

    static func isProcessAlive(pid: Int32) -> Bool {
        // kill(pid, 0) checks existence without sending a signal
        kill(pid, 0) == 0
    }

    static func parseEnvString(_ content: String) -> [String: String] {
        var env: [String: String] = [:]

        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            if let eqIndex = trimmed.firstIndex(of: "=") {
                let key = String(trimmed[..<eqIndex]).trimmingCharacters(in: .whitespaces)
                var value = String(trimmed[trimmed.index(after: eqIndex)...]).trimmingCharacters(in: .whitespaces)
                // Strip surrounding quotes
                if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                   (value.hasPrefix("'") && value.hasSuffix("'")) {
                    value = String(value.dropFirst().dropLast())
                }
                if !key.isEmpty {
                    env[key] = value
                }
            }
        }
        return env
    }

    // MARK: - Private

    private static func mergedEnvironment(extra: [String: String]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        for (key, value) in extra {
            env[key] = value
        }
        return env
    }

    static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }
}
