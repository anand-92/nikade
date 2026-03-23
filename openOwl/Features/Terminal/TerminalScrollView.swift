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
    private let scrollView: NSScrollView
    private let documentView: NSView
    let terminalView: TerminalNSView

    private var isLiveScrolling = false
    private var userScrolledUp = false
    private var lastSentRow: Int?
    private var observers: [NSObjectProtocol] = []
    private var terminalShouldBeVisible = true

    /// Current scrollbar state from ghostty core
    var scrollbarState: TerminalScrollbarState?

    /// Current cell size from ghostty core (pixels per character cell)
    var cellSize: CGSize = .zero

    init(terminalView: TerminalNSView) {
        self.terminalView = terminalView

        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.usesPredominantAxisScrolling = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.contentView.clipsToBounds = false

        documentView = NSView(frame: .zero)
        scrollView.documentView = documentView
        documentView.addSubview(terminalView)

        super.init(frame: .zero)
        addSubview(scrollView)

        terminalView.onUserScroll = { [weak self] in
            self?.userScrolledUp = true
        }

        // Accept file/URL/text drops on this top-level view (SwiftUI hosts this directly)
        registerForDraggedTypes([.fileURL, .URL, .string])

        // Listen for scroll position changes
        scrollView.contentView.postsBoundsChangedNotifications = true
        observers.append(NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.synchronizeSurfaceView()
        })

        // Live scroll tracking
        observers.append(NotificationCenter.default.addObserver(
            forName: NSScrollView.willStartLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            self?.isLiveScrolling = true
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: NSScrollView.didEndLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            self?.isLiveScrolling = false
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: NSScrollView.didLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            self?.handleLiveScroll()
        })

        // Re-evaluate scroller style when system preference changes
        observers.append(NotificationCenter.default.addObserver(
            forName: NSScroller.preferredScrollerStyleDidChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self, let state = self.scrollbarState else { return }
            self.updateScrollerVisibility(state)
        })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        terminalView.frame.size = scrollView.bounds.size
        documentView.frame.size.width = scrollView.bounds.width
        synchronizeScrollView()
        synchronizeSurfaceView()
    }

    // MARK: - Public API

    /// Called when ghostty sends GHOSTTY_ACTION_SCROLLBAR
    func updateScrollbar(_ state: TerminalScrollbarState) {
        scrollbarState = state
        synchronizeScrollView()
        updateScrollerVisibility(state)
    }

    /// Show scrollbar when there is scrollback content.
    /// Overlay scrollers auto-fade and never appear because scrollWheel events
    /// bypass the NSScrollView entirely. Switch to legacy style (always visible)
    /// when the terminal has scrollback, revert to overlay when there's none.
    private func updateScrollerVisibility(_ state: TerminalScrollbarState) {
        let hasScrollback = state.total > state.len
        let wantLegacy = hasScrollback
        let currentlyLegacy = scrollView.scrollerStyle == .legacy
        if wantLegacy != currentlyLegacy {
            scrollView.scrollerStyle = wantLegacy ? .legacy : .overlay
        }
    }

    /// Called when ghostty sends GHOSTTY_ACTION_CELL_SIZE
    func updateCellSize(_ size: CGSize) {
        cellSize = size
        synchronizeScrollView()
    }

    func setTerminalVisibility(_ isVisible: Bool) {
        terminalShouldBeVisible = isVisible
        terminalView.setSurfaceVisibility(isVisible)
    }

    // MARK: - Scrolling Sync

    /// Updates document height and scroll position from ghostty state
    private func synchronizeScrollView() {
        documentView.frame.size.height = documentHeight()

        if !isLiveScrolling {
            let ch = cellSize.height
            if ch > 0, let sb = scrollbarState {
                let isAtBottom = sb.offset + sb.len >= sb.total

                // Track whether the user has scrolled away from the bottom.
                // Reset when ghostty reports we're at the bottom (user scrolled
                // back down, or terminal was reset).
                if isAtBottom {
                    userScrolledUp = false
                }

                // Don't auto-scroll when the user is viewing scrollback —
                // let them read without the view jumping to the bottom on
                // every new line of output.
                if !userScrolledUp {
                    let offsetY = CGFloat(sb.total - sb.offset - sb.len) * ch
                    scrollView.contentView.scroll(to: CGPoint(x: 0, y: offsetY))
                    lastSentRow = Int(sb.offset)
                }
            }
        }

        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    /// Keeps the terminal surface positioned at the visible rect
    private func synchronizeSurfaceView() {
        let visibleRect = scrollView.contentView.documentVisibleRect
        terminalView.frame.origin = visibleRect.origin
    }

    /// User is dragging the scrollbar → tell ghostty core which row to show
    private func handleLiveScroll() {
        let ch = cellSize.height
        guard ch > 0 else { return }

        let visibleRect = scrollView.contentView.documentVisibleRect
        let docHeight = documentView.frame.height
        let scrollOffset = docHeight - visibleRect.origin.y - visibleRect.height
        let row = Int(scrollOffset / ch)

        // Detect if the user scrolled away from the bottom
        let nearBottom = visibleRect.origin.y <= ch
        if !nearBottom {
            userScrolledUp = true
        }

        guard row != lastSentRow else { return }
        lastSentRow = row

        let action = "scroll_to_row:\(row)"
        terminalView.performBindingAction(action)
    }

    /// Calculate document view height from scrollbar state
    private func documentHeight() -> CGFloat {
        let contentHeight = scrollView.contentSize.height
        let ch = cellSize.height
        if ch > 0, let sb = scrollbarState {
            let documentGridHeight = CGFloat(sb.total) * ch
            let padding = contentHeight - (CGFloat(sb.len) * ch)
            return documentGridHeight + padding
        }
        return contentHeight
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

    // MARK: - Mouse (legacy scroller support)

    override func mouseMoved(with event: NSEvent) {
        guard NSScroller.preferredScrollerStyle == .legacy else { return }
        scrollView.flashScrollers()
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach { removeTrackingArea($0) }
        super.updateTrackingAreas()
        guard let scroller = scrollView.verticalScroller else { return }
        addTrackingArea(NSTrackingArea(
            rect: convert(scroller.bounds, from: scroller),
            options: [.mouseMoved, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        ))
    }
}
