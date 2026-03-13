import AppKit
import QuartzCore

/// Core terminal NSView backed by CAMetalLayer + ghostty_surface_t.
/// Handles keyboard, mouse, resize, and focus events.
class TerminalNSView: NSView {
    private var surface: ghostty_surface_t?
    private let ghosttyApp: ghostty_app_t
    private var metalLayer: CAMetalLayer!
    private var trackingArea: NSTrackingArea?

    /// Reference to the app manager for clipboard routing.
    weak var appManager: GhosttyAppManager?

    init(ghosttyApp: ghostty_app_t) {
        self.ghosttyApp = ghosttyApp
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Layer Setup

    override func makeBackingLayer() -> CALayer {
        let layer = CAMetalLayer()
        layer.device = MTLCreateSystemDefaultDevice()
        layer.isOpaque = true
        layer.contentsScale = window?.backingScaleFactor ?? 2.0
        metalLayer = layer
        return layer
    }

    override var wantsUpdateLayer: Bool { true }

    // MARK: - Surface Lifecycle

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard let window, surface == nil else { return }

        // Update metal layer scale
        metalLayer.contentsScale = window.backingScaleFactor

        // Create surface config
        var surfaceConfig = ghostty_surface_config_new()
        surfaceConfig.platform_tag = GHOSTTY_PLATFORM_MACOS
        surfaceConfig.platform.macos.nsview = Unmanaged.passUnretained(self).toOpaque()
        surfaceConfig.userdata = Unmanaged.passUnretained(self).toOpaque()
        surfaceConfig.scale_factor = Double(window.backingScaleFactor)
        surfaceConfig.font_size = 0 // use config default

        surface = ghostty_surface_new(ghosttyApp, &surfaceConfig)

        guard surface != nil else {
            NSLog("openOwl: Failed to create ghostty surface")
            return
        }

        // Set initial size
        let fbSize = convertToBacking(bounds.size)
        ghostty_surface_set_size(surface, UInt32(fbSize.width), UInt32(fbSize.height))
        ghostty_surface_set_content_scale(surface, Double(window.backingScaleFactor), Double(window.backingScaleFactor))

        // Register as active surface for clipboard callbacks
        appManager?.activeSurface = surface

        // Setup tracking area for mouse events
        setupTrackingArea()

        // Become first responder to receive key events
        window.makeFirstResponder(self)
    }

    override func removeFromSuperview() {
        if let surface {
            if appManager?.activeSurface == surface {
                appManager?.activeSurface = nil
            }
            ghostty_surface_free(surface)
            self.surface = nil
        }
        super.removeFromSuperview()
    }

    // MARK: - First Responder

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        if let surface {
            ghostty_surface_set_focus(surface, true)
            appManager?.activeSurface = surface
        }
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        if let surface {
            ghostty_surface_set_focus(surface, false)
        }
        return super.resignFirstResponder()
    }

    // MARK: - Resize

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard let surface else { return }

        let fbSize = convertToBacking(newSize)
        ghostty_surface_set_size(surface, UInt32(fbSize.width), UInt32(fbSize.height))
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        guard let window, let surface else { return }
        metalLayer?.contentsScale = window.backingScaleFactor
        ghostty_surface_set_content_scale(
            surface,
            Double(window.backingScaleFactor),
            Double(window.backingScaleFactor)
        )
    }

    // MARK: - Keyboard Input

    override func keyDown(with event: NSEvent) {
        guard let surface else {
            super.keyDown(with: event)
            return
        }

        let key = GhosttyInput.keyEvent(from: event, action: GHOSTTY_ACTION_PRESS)
        let handled = ghostty_surface_key(surface, key)
        if !handled {
            // Let interpretKeyEvents handle IME input
            interpretKeyEvents([event])
        }
    }

    override func keyUp(with event: NSEvent) {
        guard let surface else {
            super.keyUp(with: event)
            return
        }

        let key = GhosttyInput.keyEvent(from: event, action: GHOSTTY_ACTION_RELEASE)
        _ = ghostty_surface_key(surface, key)
    }

    override func flagsChanged(with event: NSEvent) {
        guard let surface else {
            super.flagsChanged(with: event)
            return
        }

        let key = GhosttyInput.keyEvent(from: event, action: GHOSTTY_ACTION_PRESS)
        _ = ghostty_surface_key(surface, key)
    }

    // MARK: - Mouse Input

    override func mouseDown(with event: NSEvent) {
        guard let surface else { return }
        window?.makeFirstResponder(self)

        let point = convert(event.locationInWindow, from: nil)
        let fbPoint = convertToBacking(point)
        let mods = GhosttyInput.modifierFlags(from: event)

        ghostty_surface_mouse_pos(surface, fbPoint.x, fbPoint.y, mods)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, mods)
    }

    override func mouseUp(with event: NSEvent) {
        guard let surface else { return }

        let point = convert(event.locationInWindow, from: nil)
        let fbPoint = convertToBacking(point)
        let mods = GhosttyInput.modifierFlags(from: event)

        ghostty_surface_mouse_pos(surface, fbPoint.x, fbPoint.y, mods)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, mods)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let surface else { return }
        let mods = GhosttyInput.modifierFlags(from: event)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, mods)
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let surface else { return }
        let mods = GhosttyInput.modifierFlags(from: event)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, mods)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let surface else { return }
        let point = convert(event.locationInWindow, from: nil)
        let fbPoint = convertToBacking(point)
        let mods = GhosttyInput.modifierFlags(from: event)
        ghostty_surface_mouse_pos(surface, fbPoint.x, fbPoint.y, mods)
    }

    override func mouseMoved(with event: NSEvent) {
        guard let surface else { return }
        let point = convert(event.locationInWindow, from: nil)
        let fbPoint = convertToBacking(point)
        let mods = GhosttyInput.modifierFlags(from: event)
        ghostty_surface_mouse_pos(surface, fbPoint.x, fbPoint.y, mods)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }

        // Build scroll mods as ghostty_input_scroll_mods_t (packed int)
        var scrollMods: Int32 = 0
        if event.hasPreciseScrollingDeltas {
            scrollMods |= 1 // precision bit
        }
        if event.momentumPhase != [] {
            // Set momentum bits based on phase
            if event.momentumPhase == .began {
                scrollMods |= (1 << 1) // GHOSTTY_MOUSE_MOMENTUM_BEGAN
            } else if event.momentumPhase == .changed {
                scrollMods |= (2 << 1) // GHOSTTY_MOUSE_MOMENTUM_CHANGED
            } else if event.momentumPhase == .ended {
                scrollMods |= (3 << 1) // GHOSTTY_MOUSE_MOMENTUM_ENDED
            }
        }

        ghostty_surface_mouse_scroll(
            surface,
            event.scrollingDeltaX,
            event.scrollingDeltaY,
            scrollMods
        )
    }

    // MARK: - Tracking Area

    private func setupTrackingArea() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }
}

// MARK: - NSTextInputClient

extension TerminalNSView: NSTextInputClient {
    func insertText(_ string: Any, replacementRange: NSRange) {
        guard let surface else { return }
        guard let str = string as? String else { return }
        str.withCString { cstr in
            ghostty_surface_text(surface, cstr, UInt(str.utf8.count))
        }
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        guard let surface else { return }
        if let str = string as? String {
            str.withCString { cstr in
                ghostty_surface_preedit(surface, cstr, UInt(str.utf8.count))
            }
        }
    }

    func unmarkText() {
        guard let surface else { return }
        ghostty_surface_preedit(surface, nil, 0)
    }

    func hasMarkedText() -> Bool { false }

    func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }

    func markedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let surface, let window else { return .zero }
        var x: Double = 0, y: Double = 0, w: Double = 0, h: Double = 0
        ghostty_surface_ime_point(surface, &x, &y, &w, &h)
        let point = NSPoint(x: x, y: frame.height - y - h)
        let screenPoint = window.convertPoint(toScreen: convert(point, to: nil))
        return NSRect(x: screenPoint.x, y: screenPoint.y, width: w, height: h)
    }

    func characterIndex(for point: NSPoint) -> Int { 0 }
}
