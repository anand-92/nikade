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
    private let scroller: ScrollIndicatorView
    private var userScrolledUp = false
    private var terminalShouldBeVisible = true

    /// Current scrollbar state from ghostty core
    var scrollbarState: TerminalScrollbarState?

    /// Current cell size from ghostty core (pixels per character cell)
    var cellSize: CGSize = .zero

    init(terminalView: TerminalNSView) {
        self.terminalView = terminalView

        // Custom scroll indicator — a simple rounded bar drawn manually.
        // NSScroller (both overlay and legacy) doesn't render the knob
        // correctly without an NSScrollView parent.
        scroller = ScrollIndicatorView()

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
        let indicatorWidth: CGFloat = 8
        let margin: CGFloat = 2
        scroller.frame = CGRect(
            x: bounds.width - indicatorWidth - margin,
            y: margin,
            width: indicatorWidth,
            height: bounds.height - margin * 2
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

        if hasScrollback {
            let maxOffset = state.total - state.len
            let proportion = CGFloat(state.len) / CGFloat(state.total)
            let position = maxOffset > 0 ? CGFloat(state.offset) / CGFloat(maxOffset) : 0
            scroller.update(proportion: proportion, position: position)

            if state.offset != previousOffset {
                showScrollerTemporarily()
            }
        } else if scroller.alphaValue > 0 {
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

// MARK: - Scroll Indicator

/// Custom scroll indicator that draws a rounded bar.
/// NSScroller doesn't render its knob correctly without an NSScrollView parent,
/// so we draw our own minimal indicator.
class ScrollIndicatorView: NSView {
    private var proportion: CGFloat = 1
    private var position: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        alphaValue = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(proportion: CGFloat, position: CGFloat) {
        self.proportion = proportion
        self.position = position
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard proportion < 1 else { return }
        let knobHeight = max(bounds.height * proportion, 24)
        let trackSpace = bounds.height - knobHeight
        // AppKit is +Y up, but position 0 = top of scrollback.
        // position=0 → knob at top, position=1 → knob at bottom.
        let knobY = bounds.height - knobHeight - (trackSpace * position)
        let knobRect = NSRect(
            x: 1, y: knobY,
            width: bounds.width - 2, height: knobHeight
        )
        let path = NSBezierPath(roundedRect: knobRect, xRadius: 3, yRadius: 3)
        NSColor.white.withAlphaComponent(0.35).setFill()
        path.fill()
    }
}

