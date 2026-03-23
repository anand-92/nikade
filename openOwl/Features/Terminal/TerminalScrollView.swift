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
        // Always use overlay style — matches Ghostty. Legacy style takes horizontal
        // space which conflicts with the Metal layer filling the full bounds.
        scrollView.scrollerStyle = .overlay
        scrollView.appearance = NSAppearance(named: .darkAqua)
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

        // Keep overlay style even if system preference changes
        observers.append(NotificationCenter.default.addObserver(
            forName: NSScroller.preferredScrollerStyleDidChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.scrollView.scrollerStyle = .overlay
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
        // Use bounds.size for the view frames — Metal layer fills the entire area.
        // Ghostty renders text within contentSize.width (set via ghostty_surface_set_size).
        terminalView.frame.size = scrollView.bounds.size
        documentView.frame.size.width = scrollView.bounds.width
        synchronizeScrollView()
        synchronizeSurfaceView()
    }

    // MARK: - Public API

    /// Called when ghostty sends GHOSTTY_ACTION_SCROLLBAR
    func updateScrollbar(_ state: TerminalScrollbarState) {
        let previousOffset = scrollbarState?.offset
        scrollbarState = state
        synchronizeScrollView()
        // Only flash when the user is scrolling (offset changed),
        // not on every new line of output (total changed).
        // This lets the overlay scroller auto-fade when idle.
        if state.total > state.len, state.offset != previousOffset {
            scrollView.flashScrollers()
        }
        #if DEBUG
        let docH = documentView.frame.height
        let visH = scrollView.contentSize.height
        let hasScroller = scrollView.verticalScroller != nil
        let scrollerHidden = scrollView.verticalScroller?.isHidden ?? true
        NSLog("openOwl: [Scroll] total=%llu offset=%llu len=%llu docH=%.0f visH=%.0f hasScroller=%d scrollerHidden=%d",
              state.total, state.offset, state.len, docH, visH, hasScroller ? 1 : 0, scrollerHidden ? 1 : 0)
        #endif
    }

    /// Called when ghostty sends GHOSTTY_ACTION_CELL_SIZE
    func updateCellSize(_ size: CGSize) {
        #if DEBUG
        NSLog("openOwl: [Scroll] cellSize updated: %.1f x %.1f", size.width, size.height)
        #endif
        cellSize = size
        synchronizeScrollView()
    }

    func setTerminalVisibility(_ isVisible: Bool) {
        terminalShouldBeVisible = isVisible
        terminalView.setSurfaceVisibility(isVisible)
    }

    // MARK: - Scrolling Sync

    /// Updates scroller knob position/size from ghostty state.
    /// We do NOT set a tall documentView height — that would make NSScrollView
    /// consume scrollWheel events, fighting with ghostty's scroll handling.
    /// Instead, we manually control the scroller's doubleValue and knobProportion.
    private func synchronizeScrollView() {
        // Keep document height == content height so NSScrollView has nothing to scroll.
        // Scroll events pass through to TerminalNSView → ghostty.
        documentView.frame.size.height = scrollView.contentSize.height

        guard let sb = scrollbarState, sb.total > 0, sb.len > 0 else { return }

        let isAtBottom = sb.offset + sb.len >= sb.total
        if isAtBottom { userScrolledUp = false }

        // Manually set scroller knob position and size
        if let scroller = scrollView.verticalScroller {
            let maxOffset = sb.total - sb.len
            scroller.knobProportion = CGFloat(sb.len) / CGFloat(sb.total)
            scroller.doubleValue = maxOffset > 0 ? Double(sb.offset) / Double(maxOffset) : 0
        }
    }

    /// Keeps the terminal surface positioned at the visible rect
    private func synchronizeSurfaceView() {
        let visibleRect = scrollView.contentView.documentVisibleRect
        terminalView.frame.origin = visibleRect.origin
    }

    /// User is dragging the scrollbar → tell ghostty core which row to show
    private func handleLiveScroll() {
        guard let sb = scrollbarState, sb.len > 0 else { return }
        let ch = cellSize.height > 0
            ? cellSize.height
            : scrollView.contentSize.height / CGFloat(sb.len)
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

    // documentHeight() removed — we keep docH == visH to prevent NSScrollView
    // from consuming scrollWheel events. Scroller position is set manually.

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

