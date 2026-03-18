import Testing
import Foundation
@testable import openOwl

@Suite("Graph Layout")
struct GraphLayoutTests {

    private func entry(_ hash: String, parents: [String] = [], refs: String = "") -> GitLogEntry {
        GitLogEntry(
            hash: hash,
            abbreviatedHash: String(hash.prefix(7)),
            message: "commit \(hash)",
            author: "test",
            date: "2026-01-01T00:00:00Z",
            refs: refs,
            parents: parents
        )
    }

    // MARK: - Empty

    @Test func empty_returnsEmptyLayout() {
        let layout = computeGraphLayout(entries: [])
        #expect(layout.nodes.isEmpty)
        #expect(layout.segments.isEmpty)
        #expect(layout.connectors.isEmpty)
        #expect(layout.maxColumns == 0)
    }

    // MARK: - Linear history

    @Test func linearHistory_singleColumn() {
        let entries = [
            entry("aaa", parents: ["bbb"]),
            entry("bbb", parents: ["ccc"]),
            entry("ccc"),
        ]
        let layout = computeGraphLayout(entries: entries)

        #expect(layout.nodes.count == 3)
        #expect(layout.maxColumns == 1)

        // All nodes should be in column 0
        for node in layout.nodes {
            #expect(node.column == 0)
        }
    }

    @Test func linearHistory_rowsMatchOrder() {
        let entries = [
            entry("aaa", parents: ["bbb"]),
            entry("bbb", parents: ["ccc"]),
            entry("ccc"),
        ]
        let layout = computeGraphLayout(entries: entries)

        #expect(layout.nodes[0].row == 0)
        #expect(layout.nodes[1].row == 1)
        #expect(layout.nodes[2].row == 2)
    }

    // MARK: - Branch / merge

    @Test func simpleBranch_usesMultipleColumns() {
        // aaa has two parents: bbb (first parent) and ccc (merge parent)
        let entries = [
            entry("aaa", parents: ["bbb", "ccc"]),
            entry("bbb", parents: ["ddd"]),
            entry("ccc", parents: ["ddd"]),
            entry("ddd"),
        ]
        let layout = computeGraphLayout(entries: entries)

        #expect(layout.nodes.count == 4)
        #expect(layout.maxColumns >= 2)
    }

    @Test func merge_createsConnector() {
        let entries = [
            entry("aaa", parents: ["bbb", "ccc"]),
            entry("bbb", parents: ["ddd"]),
            entry("ccc", parents: ["ddd"]),
            entry("ddd"),
        ]
        let layout = computeGraphLayout(entries: entries)

        // Should have at least one connector (merge line)
        #expect(!layout.connectors.isEmpty)
    }

    // MARK: - Single commit

    @Test func singleCommit_oneNode() {
        let entries = [entry("aaa")]
        let layout = computeGraphLayout(entries: entries)

        #expect(layout.nodes.count == 1)
        #expect(layout.nodes[0].hash == "aaa")
        #expect(layout.nodes[0].column == 0)
        #expect(layout.nodes[0].row == 0)
        #expect(layout.segments.isEmpty)
    }

    // MARK: - Segments

    @Test func linearHistory_createsSegmentsBetweenRows() {
        let entries = [
            entry("aaa", parents: ["bbb"]),
            entry("bbb", parents: ["ccc"]),
            entry("ccc"),
        ]
        let layout = computeGraphLayout(entries: entries)

        // 2 segments: row 0→1 and row 1→2
        #expect(layout.segments.count == 2)
    }
}
