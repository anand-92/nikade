import Foundation

final class CommitMessageGenerator {
    private var process: Process?
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()

    func start() {
        guard process == nil || process?.isRunning == false else { return }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-l"]
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stdoutPipe

        do {
            try proc.run()
            process = proc
            send("PS1='' PS2='' PROMPT='' RPROMPT=''")
        } catch {
            NSLog("CommitMessageGenerator: failed to start shell: \(error)")
        }
    }

    func generate(diff: String) async throws -> String {
        if process == nil || process?.isRunning == false {
            start()
        }
        guard let process, process.isRunning else {
            throw GeneratorError.shellNotRunning
        }

        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("openowl-diff-\(UUID().uuidString).txt")
        try diff.write(to: tmpFile, atomically: true, encoding: .utf8)

        let id = Int.random(in: 100000...999999)
        let startMarker = "___OWLSTART\(id)___"
        let endMarker = "___OWLEND\(id)___"

        let prompt = "Write a commit message for this diff. One summary line, then bullet points. Only output the message."

        return try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var buffer = ""
            var resumed = false

            // Timeout after 30s
            let timeoutItem = DispatchWorkItem {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                try? FileManager.default.removeItem(at: tmpFile)
                continuation.resume(throwing: GeneratorError.timeout)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timeoutItem)

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }

                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }

                buffer += str

                guard buffer.contains(endMarker) else { return }
                resumed = true
                timeoutItem.cancel()
                try? FileManager.default.removeItem(at: tmpFile)

                if let startRange = buffer.range(of: startMarker),
                   let endRange = buffer.range(of: endMarker) {
                    let output = String(buffer[startRange.upperBound..<endRange.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: GeneratorError.emptyResponse)
                }
            }

            let cmd = "echo '\(startMarker)'; cat '\(tmpFile.path)' | claude -p '\(prompt)' 2>/dev/null; echo '\(endMarker)'"
            send(cmd)
        }
    }

    func stop() {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
    }

    private func send(_ command: String) {
        stdinPipe.fileHandleForWriting.write((command + "\n").data(using: .utf8)!)
    }

    enum GeneratorError: LocalizedError {
        case shellNotRunning
        case emptyResponse
        case timeout

        var errorDescription: String? {
            switch self {
            case .shellNotRunning: return "Background shell failed to start"
            case .emptyResponse: return "No response from claude CLI. Is it installed?"
            case .timeout: return "Commit message generation timed out"
            }
        }
    }
}
