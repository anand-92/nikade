import Testing
import Foundation
@testable import openOwl

@Suite("Deployment Log Throttle")
struct DeploymentLogThrottleTests {

    // MARK: - Buffer Accumulation

    @Test @MainActor func appendLog_buffersWithoutImmediateFlush() {
        let store = DeploymentStore()
        store.appendLog("line 1\n")
        store.appendLog("line 2\n")

        #expect(store.logContent.isEmpty)
        #expect(store.logBuffer == "line 1\nline 2\n")
    }

    @Test @MainActor func appendLog_multipleChunks_accumulate() {
        let store = DeploymentStore()
        for i in 0..<50 {
            store.appendLog("chunk-\(i) ")
        }

        #expect(store.logContent.isEmpty)
        #expect(store.logBuffer.contains("chunk-0"))
        #expect(store.logBuffer.contains("chunk-49"))
    }

    // MARK: - Flush

    @Test @MainActor func flushLogBuffer_movesBufferToLogContent() {
        let store = DeploymentStore()
        store.appendLog("hello world\n")
        store.flushLogBuffer()

        #expect(store.logContent == "hello world\n")
        #expect(store.logBuffer.isEmpty)
    }

    @Test @MainActor func flushLogBuffer_emptyBuffer_noOp() {
        let store = DeploymentStore()
        store.flushLogBuffer()

        #expect(store.logContent.isEmpty)
        #expect(store.logBuffer.isEmpty)
    }

    @Test @MainActor func flushLogBuffer_multipleFlushes_appendToLogContent() {
        let store = DeploymentStore()

        store.appendLog("batch-1\n")
        store.flushLogBuffer()

        store.appendLog("batch-2\n")
        store.flushLogBuffer()

        #expect(store.logContent == "batch-1\nbatch-2\n")
    }

    @Test @MainActor func flushLogBuffer_doubleFlush_isIdempotent() {
        let store = DeploymentStore()
        store.appendLog("data\n")
        store.flushLogBuffer()
        store.flushLogBuffer() // second flush with empty buffer

        #expect(store.logContent == "data\n")
    }

    // MARK: - Content Cap

    @Test @MainActor func flushLogBuffer_capsLogContentAt100KB() {
        let store = DeploymentStore()

        // Build up 90KB
        let largePrefix = String(repeating: "A", count: 90_000)
        store.appendLog(largePrefix)
        store.flushLogBuffer()
        #expect(store.logContent.count == 90_000)

        // Append another 20KB → total 110KB, should be capped
        let overflow = String(repeating: "B", count: 20_000)
        store.appendLog(overflow)
        store.flushLogBuffer()

        #expect(store.logContent.count == 80_000)
        #expect(store.logContent.hasSuffix(String(repeating: "B", count: 20_000)))
    }

    @Test @MainActor func flushLogBuffer_exactlyAtCap_noTruncation() {
        let store = DeploymentStore()

        let exact = String(repeating: "X", count: 100_000)
        store.appendLog(exact)
        store.flushLogBuffer()

        // 100_000 is not > 100_000, so no cap triggered
        #expect(store.logContent.count == 100_000)
    }

    @Test @MainActor func flushLogBuffer_justOverCap_truncates() {
        let store = DeploymentStore()

        let overBy1 = String(repeating: "Y", count: 100_001)
        store.appendLog(overBy1)
        store.flushLogBuffer()

        #expect(store.logContent.count == 80_000)
    }

    // MARK: - Active Stream Tracking

    @Test @MainActor func stop_removesActiveStreamID() async {
        let store = DeploymentStore()
        store.activeStreamIDs.insert("deploy-1")
        #expect(store.activeStreamIDs.contains("deploy-1"))

        await store.stop(id: "deploy-1")

        #expect(!store.activeStreamIDs.contains("deploy-1"))
    }

    @Test @MainActor func stop_nonExistentID_doesNotCrash() async {
        let store = DeploymentStore()
        await store.stop(id: "nonexistent")

        #expect(store.activeStreamIDs.isEmpty)
    }

    @Test @MainActor func activeStreamIDs_multipleStreams() async {
        let store = DeploymentStore()
        store.activeStreamIDs.insert("a")
        store.activeStreamIDs.insert("b")
        store.activeStreamIDs.insert("c")

        await store.stop(id: "b")

        #expect(store.activeStreamIDs == Set(["a", "c"]))
    }
}
