import AppKit

/// Scrollbar state from ghostty core: total rows, viewport offset, visible row count.
struct TerminalScrollbarState {
    let total: UInt64
    let offset: UInt64
    let len: UInt64
}

/// Wraps a TerminalNSView in an NSScrollView to provide native macOS scrollbar support.
///
/// Architecture mirrors Ghostty's SurfaceScrollView:
/// - `scrollView`: NSScrollView with overlay scrollers
/// - `documentView`: Blank NSView whose height = total scrollback in pixels
/// - `terminalView`: The actual Metal renderer, positioned to fill the visible rect
///
/// Coordinate system: AppKit is +Y-up (origin bottom-left), terminal is +Y-down (row 0 at top).
class TerminalScrollView: NSView {
    let terminalView: TerminalNSView
    private let scroller: NSScroller
    private var userScrolledUp = false
    private var terminalShouldBeVisible = true

    /// Current scrollbar state from ghostty core
    var scrollbarState: TerminalScrollbarState?

    /// Current cell size from ghostty core (pixels per character cell)
    var cellSize: CGSize = .zero

    init(terminalView: TerminalNSView) {
        self.terminalView = terminalView

        // Standalone scroller — not part of any NSScrollView.
        // This avoids NSScrollView consuming scrollWheel events
        // while still providing a native macOS scrollbar visual.
        scroller = NSScroller()
        scroller.scrollerStyle = .overlay
        scroller.alphaValue = 0 // hidden until scrollback exists

        super.init(frame: .zero)
        addSubview(terminalView)
        addSubview(scroller)

        terminalView.onUserScroll = { [weak self] in
            self?.userScrolledUp = true
        }

        // Accept file/URL/text drops on this top-level view (SwiftUI hosts this directly)
        registerForDraggedTypes([.fileURL, .URL, .string])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        terminalView.frame = bounds
        // Position scroller on the right edge, overlay style
        let scrollerWidth: CGFloat = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .overlay)
        scroller.frame = CGRect(
            x: bounds.width - scrollerWidth,
            y: 0,
            width: scrollerWidth,
            height: bounds.height
        )
    }

    // MARK: - Public API

    /// Called when ghostty sends GHOSTTY_ACTION_SCROLLBAR
    func updateScrollbar(_ state: TerminalScrollbarState) {
        let previousOffset = scrollbarState?.offset
        scrollbarState = state

        guard state.total > 0, state.len > 0 else { return }

        let hasScrollback = state.total > state.len
        let isAtBottom = state.offset + state.len >= state.total
        if isAtBottom { userScrolledUp = false }

        // Update scroller knob
        if hasScrollback {
            let maxOffset = state.total - state.len
            scroller.knobProportion = CGFloat(state.len) / CGFloat(state.total)
            scroller.doubleValue = maxOffset > 0 ? Double(state.offset) / Double(maxOffset) : 0
            scroller.isEnabled = true

            // Show scroller when user scrolls (offset changed), fade after delay
            if state.offset != previousOffset {
                showScrollerTemporarily()
            }
        }

        // Hide scroller when there's no scrollback
        if !hasScrollback && scroller.alphaValue > 0 {
            scroller.alphaValue = 0
        }
    }

    private var scrollerFadeTimer: Timer?

    private func showScrollerTemporarily() {
        scroller.alphaValue = 0.7
        scrollerFadeTimer?.invalidate()
        scrollerFadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                self?.scroller.animator().alphaValue = 0
            }
        }
    }

    /// Called when ghostty sends GHOSTTY_ACTION_CELL_SIZE
    func updateCellSize(_ size: CGSize) {
        cellSize = size
    }

    func setTerminalVisibility(_ isVisible: Bool) {
        terminalShouldBeVisible = isVisible
        terminalView.setSurfaceVisibility(isVisible)
    }

    // MARK: - Drag & Drop (forwarded to terminalView)

    private static let acceptedDropTypes: Set<NSPasteboard.PasteboardType> = [.fileURL, .URL, .string]

    /// Reject drags on hidden terminals (opacity=0 via SwiftUI project tab switching).
    /// Without this, AppKit routes drags to invisible views in the ZStack, causing
    /// the file path to appear in the wrong project's terminal.
    private var isEffectivelyVisible: Bool {
        var view: NSView? = self
        while let v = view {
            if v.isHidden || v.alphaValue < 0.01 { return false }
            view = v.superview
        }
        return true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard isEffectivelyVisible else { return [] }
        guard let pbTypes = sender.draggingPasteboard.types,
              !Set(pbTypes).isDisjoint(with: Self.acceptedDropTypes) else { return [] }
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard isEffectivelyVisible else { return [] }
        guard let types = sender.draggingPasteboard.types,
              !Set(types).isDisjoint(with: Self.acceptedDropTypes) else { return [] }
        return .copy
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard isEffectivelyVisible else { return false }
        guard let types = sender.draggingPasteboard.types else { return false }
        return !Set(types).isDisjoint(with: Self.acceptedDropTypes)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard isEffectivelyVisible else { return false }
        return terminalView.performDragOperation(sender)
    }

}

