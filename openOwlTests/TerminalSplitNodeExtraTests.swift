import Testing
import Foundation
@testable import openOwl

@Suite("TerminalSplitNode Extra")
struct TerminalSplitNodeExtraTests {

    // MARK: - insertingPaneBeside

    @Test func insertingPaneBeside_newPaneFirst() {
        let paneA = UUID()
        let paneB = UUID()
        let node = TerminalSplitNode.leaf(paneA)

        let result = node.insertingPaneBeside(paneA, newPaneID: paneB, axis: .vertical, newPaneFirst: true)
        #expect(result != nil)

        if case .split(let axis, _, let first, let second) = result {
            #expect(axis == .vertical)
            #expect(first == .leaf(paneB))  // new pane is first
            #expect(second == .leaf(paneA))
        } else {
            Issue.record("Expected split node")
        }
    }

    @Test func insertingPaneBeside_newPaneLast() {
        let paneA = UUID()
        let paneB = UUID()
        let node = TerminalSplitNode.leaf(paneA)

        let result = node.insertingPaneBeside(paneA, newPaneID: paneB, axis: .horizontal, newPaneFirst: false)
        if case .split(_, _, let first, let second) = result {
            #expect(first == .leaf(paneA))
            #expect(second == .leaf(paneB))
        } else {
            Issue.record("Expected split node")
        }
    }

    @Test func insertingPaneBeside_nestedTarget() {
        let paneA = UUID()
        let paneB = UUID()
        let paneC = UUID()
        let tree = TerminalSplitNode.split(
            axis: .horizontal, ratio: 0.5,
            first: .leaf(paneA), second: .leaf(paneB)
        )

        let result = tree.insertingPaneBeside(paneB, newPaneID: paneC, axis: .vertical, newPaneFirst: false)
        #expect(result != nil)
        #expect(result!.leafCount == 3)
        #expect(result!.allPaneIDs.contains(paneC))
    }

    // MARK: - updatingRatio

    @Test func updatingRatio_clampsToMin() {
        let paneA = UUID()
        let paneB = UUID()
        let tree = TerminalSplitNode.split(
            axis: .horizontal, ratio: 0.5,
            first: .leaf(paneA), second: .leaf(paneB)
        )

        let result = tree.updatingRatio(forPaneID: paneA, newRatio: 0.0)
        if case .split(_, let ratio, _, _) = result {
            #expect(ratio == 0.1)  // clamped
        } else {
            Issue.record("Expected split")
        }
    }

    @Test func updatingRatio_clampsToMax() {
        let paneA = UUID()
        let paneB = UUID()
        let tree = TerminalSplitNode.split(
            axis: .horizontal, ratio: 0.5,
            first: .leaf(paneA), second: .leaf(paneB)
        )

        let result = tree.updatingRatio(forPaneID: paneA, newRatio: 1.0)
        if case .split(_, let ratio, _, _) = result {
            #expect(ratio == 0.9)  // clamped
        } else {
            Issue.record("Expected split")
        }
    }

    @Test func updatingRatio_nonExistentPane_noChange() {
        let paneA = UUID()
        let paneB = UUID()
        let tree = TerminalSplitNode.split(
            axis: .horizontal, ratio: 0.5,
            first: .leaf(paneA), second: .leaf(paneB)
        )

        let result = tree.updatingRatio(forPaneID: UUID(), newRatio: 0.8)
        #expect(result == tree)
    }

    // MARK: - normalizedPaneFrames

    @Test func normalizedPaneFrames_singleLeaf() {
        let id = UUID()
        let node = TerminalSplitNode.leaf(id)
        let frames = node.normalizedPaneFrames()

        #expect(frames.count == 1)
        let frame = frames[id]!
        #expect(frame.origin.x == 0)
        #expect(frame.origin.y == 0)
        #expect(frame.width == 1)
        #expect(frame.height == 1)
    }

    @Test func normalizedPaneFrames_splitSumsToOne() {
        let paneA = UUID()
        let paneB = UUID()
        let tree = TerminalSplitNode.split(
            axis: .horizontal, ratio: 0.3,
            first: .leaf(paneA), second: .leaf(paneB)
        )
        let frames = tree.normalizedPaneFrames()

        #expect(frames.count == 2)
        let totalWidth = frames[paneA]!.width + frames[paneB]!.width
        #expect(abs(totalWidth - 1.0) < 0.001)
    }

    // MARK: - dividerInfos

    @Test func dividerInfos_singleLeaf_empty() {
        let id = UUID()
        let node = TerminalSplitNode.leaf(id)
        let dividers = node.dividerInfos(in: CGRect(x: 0, y: 0, width: 800, height: 600))
        #expect(dividers.isEmpty)
    }

    @Test func dividerInfos_oneSplit_oneDivider() {
        let paneA = UUID()
        let paneB = UUID()
        let tree = TerminalSplitNode.split(
            axis: .horizontal, ratio: 0.5,
            first: .leaf(paneA), second: .leaf(paneB)
        )
        let dividers = tree.dividerInfos(in: CGRect(x: 0, y: 0, width: 800, height: 600))

        #expect(dividers.count == 1)
        #expect(dividers[0].axis == .horizontal)
        #expect(dividers[0].firstPaneID == paneA)
        #expect(dividers[0].secondPaneID == paneB)
    }

    @Test func dividerInfos_nestedSplit_twoDividers() {
        let paneA = UUID()
        let paneB = UUID()
        let paneC = UUID()
        let tree = TerminalSplitNode.split(
            axis: .horizontal, ratio: 0.5,
            first: .leaf(paneA),
            second: .split(
                axis: .vertical, ratio: 0.5,
                first: .leaf(paneB), second: .leaf(paneC)
            )
        )
        let dividers = tree.dividerInfos(in: CGRect(x: 0, y: 0, width: 800, height: 600))
        #expect(dividers.count == 2)
    }

    // MARK: - paneFrames vertical split

    @Test func paneFrames_verticalSplit() {
        let paneA = UUID()
        let paneB = UUID()
        let tree = TerminalSplitNode.split(
            axis: .vertical, ratio: 0.5,
            first: .leaf(paneA), second: .leaf(paneB)
        )
        let rect = CGRect(x: 0, y: 0, width: 800, height: 600)
        let frames = tree.paneFrames(in: rect)

        #expect(frames[paneA]!.height == 300)
        #expect(frames[paneB]!.height == 300)
        #expect(frames[paneA]!.width == 800)
        #expect(frames[paneB]!.width == 800)
    }

    // MARK: - Complex tree operations

    @Test func threePaneSplit_leafCount() {
        let a = UUID(), b = UUID(), c = UUID()
        let tree = TerminalSplitNode.split(
            axis: .horizontal, ratio: 0.33,
            first: .leaf(a),
            second: .split(axis: .horizontal, ratio: 0.5, first: .leaf(b), second: .leaf(c))
        )
        #expect(tree.leafCount == 3)
        #expect(tree.allPaneIDs == [a, b, c])
    }

    @Test func removingPane_fromThreePane_collapses() {
        let a = UUID(), b = UUID(), c = UUID()
        let tree = TerminalSplitNode.split(
            axis: .horizontal, ratio: 0.5,
            first: .leaf(a),
            second: .split(axis: .vertical, ratio: 0.5, first: .leaf(b), second: .leaf(c))
        )

        let result = tree.removingPane(b)!
        #expect(result.leafCount == 2)
        #expect(result.containsPane(a))
        #expect(result.containsPane(c))
        #expect(!result.containsPane(b))
    }

    @Test func equalized_nestedRatios() {
        let a = UUID(), b = UUID(), c = UUID()
        let tree = TerminalSplitNode.split(
            axis: .horizontal, ratio: 0.8,
            first: .leaf(a),
            second: .split(axis: .vertical, ratio: 0.2, first: .leaf(b), second: .leaf(c))
        )

        let equalized = tree.equalized()
        if case .split(_, let outerRatio, _, let second) = equalized {
            #expect(outerRatio == 0.5)
            if case .split(_, let innerRatio, _, _) = second {
                #expect(innerRatio == 0.5)
            }
        }
    }
}
