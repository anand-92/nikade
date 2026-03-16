import Testing
import Foundation
@testable import openOwl

@Suite("TerminalSplitNode")
struct TerminalSplitNodeTests {

    // MARK: - Leaf basics

    @Test func leaf_count() {
        let id = UUID()
        let node = TerminalSplitNode.leaf(id)
        #expect(node.leafCount == 1)
    }

    @Test func leaf_contains() {
        let id = UUID()
        let other = UUID()
        let node = TerminalSplitNode.leaf(id)
        #expect(node.containsPane(id) == true)
        #expect(node.containsPane(other) == false)
    }

    @Test func leaf_allPaneIDs() {
        let id = UUID()
        let node = TerminalSplitNode.leaf(id)
        #expect(node.allPaneIDs == [id])
    }

    // MARK: - insertingSplit

    @Test func insertingSplit_createsNewSplit() {
        let paneA = UUID()
        let paneB = UUID()
        let node = TerminalSplitNode.leaf(paneA)

        let result = node.insertingSplit(at: paneA, newPaneID: paneB, axis: .horizontal)
        #expect(result != nil)

        if case .split(let axis, let ratio, let first, let second) = result {
            #expect(axis == .horizontal)
            #expect(ratio == 0.5)
            #expect(first == .leaf(paneA))
            #expect(second == .leaf(paneB))
        } else {
            Issue.record("Expected split node")
        }
    }

    @Test func insertingSplit_wrongTarget_returnsNil() {
        let paneA = UUID()
        let paneB = UUID()
        let wrongTarget = UUID()
        let node = TerminalSplitNode.leaf(paneA)

        #expect(node.insertingSplit(at: wrongTarget, newPaneID: paneB, axis: .horizontal) == nil)
    }

    // MARK: - removingPane

    @Test func removingPane_fromLeaf() {
        let id = UUID()
        let node = TerminalSplitNode.leaf(id)
        #expect(node.removingPane(id) == nil)
    }

    @Test func removingPane_fromSplit_collapsesToSibling() {
        let paneA = UUID()
        let paneB = UUID()
        let node = TerminalSplitNode.split(
            axis: .horizontal,
            ratio: 0.5,
            first: .leaf(paneA),
            second: .leaf(paneB)
        )

        let result = node.removingPane(paneA)
        #expect(result == .leaf(paneB))
    }

    // MARK: - swappingPanes

    @Test func swappingPanes() {
        let paneA = UUID()
        let paneB = UUID()
        let node = TerminalSplitNode.split(
            axis: .horizontal,
            ratio: 0.6,
            first: .leaf(paneA),
            second: .leaf(paneB)
        )

        let swapped = node.swappingPanes(paneA, paneB)
        if case .split(_, _, let first, let second) = swapped {
            #expect(first == .leaf(paneB))
            #expect(second == .leaf(paneA))
        } else {
            Issue.record("Expected split node")
        }
    }

    // MARK: - equalized

    @Test func equalized_resetsRatios() {
        let paneA = UUID()
        let paneB = UUID()
        let node = TerminalSplitNode.split(
            axis: .horizontal,
            ratio: 0.8,
            first: .leaf(paneA),
            second: .leaf(paneB)
        )

        let equalized = node.equalized()
        if case .split(_, let ratio, _, _) = equalized {
            #expect(ratio == 0.5)
        } else {
            Issue.record("Expected split node")
        }
    }

    // MARK: - paneFrames

    @Test func paneFrames_singleLeaf() {
        let id = UUID()
        let node = TerminalSplitNode.leaf(id)
        let rect = CGRect(x: 0, y: 0, width: 800, height: 600)
        let frames = node.paneFrames(in: rect)

        #expect(frames.count == 1)
        #expect(frames[id] == rect)
    }

    @Test func paneFrames_horizontalSplit() {
        let paneA = UUID()
        let paneB = UUID()
        let node = TerminalSplitNode.split(
            axis: .horizontal,
            ratio: 0.5,
            first: .leaf(paneA),
            second: .leaf(paneB)
        )
        let rect = CGRect(x: 0, y: 0, width: 800, height: 600)
        let frames = node.paneFrames(in: rect)

        #expect(frames.count == 2)
        #expect(frames[paneA]?.width == 400)
        #expect(frames[paneB]?.width == 400)
        #expect(frames[paneA]?.height == 600)
        #expect(frames[paneB]?.height == 600)
    }
}
