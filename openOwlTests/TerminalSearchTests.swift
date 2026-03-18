import Testing
import Foundation
@testable import openOwl

@Suite("TerminalSearchState")
@MainActor
struct TerminalSearchStateTests {

    // MARK: - matchDisplay

    @Test func matchDisplay_noTotal_returnsEmpty() {
        let state = TerminalSearchState()
        state.total = nil
        state.selected = nil
        #expect(state.matchDisplay == "")
    }

    @Test func matchDisplay_totalKnown_noSelection_returnsZeroSlashTotal() {
        let state = TerminalSearchState()
        state.total = 10
        state.selected = nil
        #expect(state.matchDisplay == "0/10")
    }

    @Test func matchDisplay_ghosttySelected0Based_displayIs1Based() {
        // ghostty reports selected as 0-based; UI should show 1-based
        let state = TerminalSearchState()
        state.total = 15
        state.selected = 0   // first match from ghostty
        #expect(state.matchDisplay == "1/15")
    }

    @Test func matchDisplay_lastMatch() {
        let state = TerminalSearchState()
        state.total = 5
        state.selected = 4  // last match (0-based index 4 → display "5")
        #expect(state.matchDisplay == "5/5")
    }

    @Test func matchDisplay_midMatch() {
        let state = TerminalSearchState()
        state.total = 20
        state.selected = 9  // 0-based 9 → display "10"
        #expect(state.matchDisplay == "10/20")
    }
}

@Suite("TerminalWorkspaceStore — drag cancel")
@MainActor
struct PaneDragCancelTests {

    @Test func cancelDragIfActive_noop_whenNoActiveDrag() {
        let store = TerminalWorkspaceStore()
        store.draggingPaneID = nil

        store.cancelDragIfActive()

        #expect(store.draggingPaneID == nil)
        #expect(store.dragOverPaneID == nil)
        #expect(store.dropZone == nil)
    }

    @Test func cancelDragIfActive_clearsAllDragState() {
        let store = TerminalWorkspaceStore()
        let paneA = UUID()
        let paneB = UUID()
        store.draggingPaneID = paneA
        store.dragOverPaneID = paneB
        store.dropZone = .center

        store.cancelDragIfActive()

        #expect(store.draggingPaneID == nil)
        #expect(store.dragOverPaneID == nil)
        #expect(store.dropZone == nil)
    }

    @Test func cancelDragIfActive_idempotent() {
        let store = TerminalWorkspaceStore()
        store.draggingPaneID = UUID()

        store.cancelDragIfActive()
        store.cancelDragIfActive()  // second call should be a no-op

        #expect(store.draggingPaneID == nil)
    }

    @Test func cancelDragIfActive_doesNotClearWhenAlreadyClearedByPerformDrop() {
        // Simulate: performDrop called cleanup() first, setting draggingPaneID = nil.
        // cancelDragIfActive fires next (from leftMouseUp handler).
        // dragOverPaneID should also be nil — not touched by a spurious cancel.
        let store = TerminalWorkspaceStore()
        let pane = UUID()
        store.draggingPaneID = pane
        store.dragOverPaneID = pane

        // Simulate cleanup() from performDrop
        store.draggingPaneID = nil
        store.dragOverPaneID = nil
        store.dropZone = nil

        // Then cancelDragIfActive fires — should be a no-op
        store.cancelDragIfActive()

        #expect(store.draggingPaneID == nil)
        #expect(store.dragOverPaneID == nil)
    }
}
