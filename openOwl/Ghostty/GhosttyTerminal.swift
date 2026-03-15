import AppKit
import QuartzCore

/// Core terminal NSView backed by CAMetalLayer + ghostty_surface_t.
/// Keyboard, mouse, resize, focus — mirrors Ghostty SurfaceView_AppKit.swift.
///
/// Known workaround:
/// - Composing keyAction skipped: key encoder leaks first character during composition.
class TerminalNSView: NSView {
    private var surface: ghostty_surface_t?
    private let ghosttyApp: ghostty_app_t
    private let paneID: UUID
    private var metalLayer: CAMetalLayer!
    private var trackingArea: NSTrackingArea?
    private var markedText = NSMutableAttributedString()
    private var keyTextAccumulator: [String]?

    weak var appManager: GhosttyAppManager?
    var onFocus: (() -> Void)?
    var paneIdentifier: UUID { paneID }

    init(ghosttyApp: ghostty_app_t, paneID: UUID) {
        self.ghosttyApp = ghosttyApp
        self.paneID = paneID
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

        metalLayer.contentsScale = window.backingScaleFactor

        var surfaceConfig = ghostty_surface_config_new()
        surfaceConfig.platform_tag = GHOSTTY_PLATFORM_MACOS
        surfaceConfig.platform = ghostty_platform_u(macos: ghostty_platform_macos_s(
            nsview: Unmanaged.passUnretained(self).toOpaque()
        ))
        surfaceConfig.userdata = Unmanaged.passUnretained(self).toOpaque()
        surfaceConfig.scale_factor = Double(window.backingScaleFactor)
        surfaceConfig.font_size = 0

        // Set working directory from process cwd (set by syncActiveProjectContext)
        let cwd = FileManager.default.currentDirectoryPath
        var cwdPtr = strdup(cwd)
        surfaceConfig.working_directory = UnsafePointer(cwdPtr)

        // Inject TERMINFO_DIRS so the shell can find xterm-ghostty terminfo
        let resourcesPath = Bundle.main.resourceURL?
            .appendingPathComponent("ghostty-resources/terminfo").path
        var envVars: [ghostty_env_var_s] = []
        var envStorage: [UnsafeMutablePointer<CChar>] = []

        if let terminfoPath = resourcesPath {
            let keyPtr = strdup("TERMINFO_DIRS")!
            let valPtr = strdup(terminfoPath)!
            envStorage.append(contentsOf: [keyPtr, valPtr])
            envVars.append(ghostty_env_var_s(key: keyPtr, value: valPtr))
        }

        if !envVars.isEmpty {
            envVars.withUnsafeMutableBufferPointer { buf in
                surfaceConfig.env_vars = buf.baseAddress
                surfaceConfig.env_var_count = buf.count
                self.surface = ghostty_surface_new(self.ghosttyApp, &surfaceConfig)
            }
        } else {
            surface = ghostty_surface_new(ghosttyApp, &surfaceConfig)
        }
        for ptr in envStorage { free(ptr) }
        free(cwdPtr); cwdPtr = nil

        guard surface != nil else {
            NSLog("openOwl: Failed to create ghostty surface")
            return
        }

        let fbSize = convertToBacking(bounds.size)
        if fbSize.width > 0 && fbSize.height > 0 {
            ghostty_surface_set_size(surface, UInt32(fbSize.width), UInt32(fbSize.height))
        }
        ghostty_surface_set_content_scale(surface, Double(window.backingScaleFactor), Double(window.backingScaleFactor))

        if let surface {
            appManager?.register(surface: surface, for: paneID, view: self)
        }

        setupTrackingArea()
        window.makeFirstResponder(self)
    }

    override func removeFromSuperview() {
        if let surface {
            appManager?.unregisterPane(paneID)
            ghostty_surface_free(surface)
            self.surface = nil
        }
        super.removeFromSuperview()
    }

    // MARK: - Public API

    func sendText(_ text: String) {
        guard let surface else { return }
        text.withCString { cstr in
            ghostty_surface_text(surface, cstr, UInt(text.utf8.count))
        }
    }

    // MARK: - First Responder

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        if let surface {
            ghostty_surface_set_focus(surface, true)
            appManager?.activeSurface = surface
            onFocus?()
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
            interpretKeyEvents([event])
            return
        }

        let translationEvent = translatedKeyEvent(for: event, surface: surface)
        let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS

        keyTextAccumulator = []
        defer { keyTextAccumulator = nil }

        let markedTextBefore = markedText.length > 0
        interpretKeyEvents([translationEvent])
        syncPreedit(clearIfNeeded: markedTextBefore)

        let acc = keyTextAccumulator ?? []
        if !acc.isEmpty {
            for text in acc {
                _ = keyAction(action, event: event, translationEvent: translationEvent, text: text)
            }
        } else if markedText.length > 0 || markedTextBefore {
            // Composing — skip keyAction. See class doc for workaround details.
        } else {
            _ = keyAction(
                action,
                event: event,
                translationEvent: translationEvent,
                text: GhosttyInput.ghosttyCharacters(from: translationEvent)
            )
        }
    }

    override func keyUp(with event: NSEvent) {
        _ = keyAction(GHOSTTY_ACTION_RELEASE, event: event)
    }

    override func flagsChanged(with event: NSEvent) {
        guard surface != nil else {
            super.flagsChanged(with: event)
            return
        }

        if hasMarkedText() { return }

        let mod: UInt32
        switch event.keyCode {
        case 0x39: mod = GHOSTTY_MODS_CAPS.rawValue
        case 0x38, 0x3C: mod = GHOSTTY_MODS_SHIFT.rawValue
        case 0x3B, 0x3E: mod = GHOSTTY_MODS_CTRL.rawValue
        case 0x3A, 0x3D: mod = GHOSTTY_MODS_ALT.rawValue
        case 0x37, 0x36: mod = GHOSTTY_MODS_SUPER.rawValue
        default: return
        }

        let mods = GhosttyInput.ghosttyMods(event.modifierFlags)
        var action = GHOSTTY_ACTION_RELEASE
        if mods.rawValue & mod != 0 {
            let sidePressed: Bool
            switch event.keyCode {
            case 0x3C:
                sidePressed = event.modifierFlags.rawValue & UInt(NX_DEVICERSHIFTKEYMASK) != 0
            case 0x3E:
                sidePressed = event.modifierFlags.rawValue & UInt(NX_DEVICERCTLKEYMASK) != 0
            case 0x3D:
                sidePressed = event.modifierFlags.rawValue & UInt(NX_DEVICERALTKEYMASK) != 0
            case 0x36:
                sidePressed = event.modifierFlags.rawValue & UInt(NX_DEVICERCMDKEYMASK) != 0
            default:
                sidePressed = true
            }
            if sidePressed {
                action = GHOSTTY_ACTION_PRESS
            }
        }

        _ = keyAction(action, event: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, let surface else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Intercept Cmd+V (paste) to avoid reentrancy crash:
        // ghostty_surface_key → paste binding → read_clipboard_cb →
        // ghostty_surface_complete_clipboard_request would re-enter the surface.
        if flags == .command, event.charactersIgnoringModifiers == "v" {
            let value = NSPasteboard.general.string(forType: .string) ?? ""
            guard !value.isEmpty else { return true }
            value.withCString { ptr in
                ghostty_surface_text(surface, ptr, UInt(value.utf8.count))
            }
            return true
        }

        // Intercept Cmd+C (copy)
        if flags == .command, event.charactersIgnoringModifiers == "c" {
            ghostty_surface_binding_action(surface, "copy_to_clipboard", 0)
            return true
        }

        return false
    }

    override func insertText(_ insertString: Any) {
        insertText(insertString, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    override func doCommand(by selector: Selector) {
        // Intentionally empty — prevents NSBeep for unhandled key commands.
    }

    // MARK: - Mouse Input

    override func mouseDown(with event: NSEvent) {
        guard let surface else { return }
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        let mods = GhosttyInput.modifierFlags(from: event)
        ghostty_surface_mouse_pos(surface, point.x, bounds.height - point.y, mods)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, mods)
    }

    override func mouseUp(with event: NSEvent) {
        guard let surface else { return }
        let point = convert(event.locationInWindow, from: nil)
        let mods = GhosttyInput.modifierFlags(from: event)
        ghostty_surface_mouse_pos(surface, point.x, bounds.height - point.y, mods)
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
        let mods = GhosttyInput.modifierFlags(from: event)
        ghostty_surface_mouse_pos(surface, point.x, bounds.height - point.y, mods)
    }

    override func mouseMoved(with event: NSEvent) {
        guard let surface else { return }
        let point = convert(event.locationInWindow, from: nil)
        let mods = GhosttyInput.modifierFlags(from: event)
        ghostty_surface_mouse_pos(surface, point.x, bounds.height - point.y, mods)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        var scrollMods: Int32 = 0
        if event.hasPreciseScrollingDeltas {
            scrollMods |= 1
        }
        if event.momentumPhase != [] {
            if event.momentumPhase == .began {
                scrollMods |= (1 << 1)
            } else if event.momentumPhase == .changed {
                scrollMods |= (2 << 1)
            } else if event.momentumPhase == .ended {
                scrollMods |= (3 << 1)
            }
        }
        ghostty_surface_mouse_scroll(surface, event.scrollingDeltaX, event.scrollingDeltaY, scrollMods)
    }

    // MARK: - Drag & Drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        hasFileURLs(in: sender.draggingPasteboard) ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        hasFileURLs(in: sender.draggingPasteboard) ? .copy : []
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        hasFileURLs(in: sender.draggingPasteboard)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let surface else { return false }
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let droppedURLs = (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]) ?? []
        let paths = droppedURLs.map { $0.standardizedFileURL.path }.uniquedPreservingOrder()
        guard !paths.isEmpty else { return false }
        window?.makeFirstResponder(self)
        let payload = paths.map(Self.shellEscapedPath).joined(separator: " ") + " "
        payload.withCString { cstr in
            ghostty_surface_text(surface, cstr, UInt(payload.utf8.count))
        }
        return true
    }

    // MARK: - Private Helpers

    private func setupTrackingArea() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    private func hasFileURLs(in pasteboard: NSPasteboard) -> Bool {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] else {
            return false
        }
        return !urls.isEmpty
    }

    private static func shellEscapedPath(_ path: String) -> String {
        let escaped = path.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "'\(escaped)'"
    }

    private func keyAction(
        _ action: ghostty_input_action_e,
        event: NSEvent,
        translationEvent: NSEvent? = nil,
        text: String? = nil,
        composing: Bool = false
    ) -> Bool {
        guard let surface else { return false }

        var key = GhosttyInput.keyEvent(
            from: event,
            action: action,
            translationMods: translationEvent?.modifierFlags
        )
        key.composing = composing

        if let text, !text.isEmpty,
           let codepoint = text.utf8.first, codepoint >= 0x20 {
            return text.withCString { ptr in
                key.text = ptr
                return ghostty_surface_key(surface, key)
            }
        } else {
            return ghostty_surface_key(surface, key)
        }
    }

    private func translatedKeyEvent(for event: NSEvent, surface: ghostty_surface_t) -> NSEvent {
        let translationModsGhostty = GhosttyInput.eventModifierFlags(
            mods: ghostty_surface_key_translation_mods(
                surface,
                GhosttyInput.ghosttyMods(event.modifierFlags)
            )
        )
        var translationMods = event.modifierFlags
        for flag in [NSEvent.ModifierFlags.shift, .control, .option, .command] {
            if translationModsGhostty.contains(flag) {
                translationMods.insert(flag)
            } else {
                translationMods.remove(flag)
            }
        }
        if translationMods == event.modifierFlags {
            return event
        }
        return NSEvent.keyEvent(
            with: event.type,
            location: event.locationInWindow,
            modifierFlags: translationMods,
            timestamp: event.timestamp,
            windowNumber: event.windowNumber,
            context: nil,
            characters: event.characters(byApplyingModifiers: translationMods) ?? "",
            charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
            isARepeat: event.isARepeat,
            keyCode: event.keyCode
        ) ?? event
    }

    private func syncPreedit(clearIfNeeded: Bool = true) {
        guard let surface else { return }
        if markedText.length > 0 {
            let str = markedText.string
            let len = str.utf8CString.count
            if len > 0 {
                str.withCString { ptr in
                    ghostty_surface_preedit(surface, ptr, UInt(len - 1))
                }
            }
        } else if clearIfNeeded {
            ghostty_surface_preedit(surface, nil, 0)
        }
    }
}

// MARK: - NSTextInputClient

extension TerminalNSView: NSTextInputClient {
    func insertText(_ string: Any, replacementRange: NSRange) {
        guard let surface else { return }
        let str: String
        switch string {
        case let attributed as NSAttributedString:
            str = attributed.string
        case let value as String:
            str = value
        default:
            return
        }

        unmarkText()

        if var accumulator = keyTextAccumulator {
            accumulator.append(str)
            keyTextAccumulator = accumulator
            return
        }

        // Direct text input outside keyDown flow (e.g. async IME commit)
        str.withCString { cstr in
            ghostty_surface_text(surface, cstr, UInt(str.utf8.count))
        }
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        switch string {
        case let attributed as NSAttributedString:
            markedText = NSMutableAttributedString(attributedString: attributed)
        case let value as String:
            markedText = NSMutableAttributedString(string: value)
        default:
            return
        }

        if keyTextAccumulator == nil {
            syncPreedit()
        }
    }

    func unmarkText() {
        if markedText.length > 0 {
            markedText.mutableString.setString("")
            syncPreedit()
        }
    }

    func hasMarkedText() -> Bool { markedText.length > 0 }

    func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }

    func markedRange() -> NSRange {
        guard markedText.length > 0 else { return NSRange(location: NSNotFound, length: 0) }
        return NSRange(location: 0, length: markedText.length)
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let surface, let window else { return .zero }
        var x: Double = 0, y: Double = 0, w: Double = 0, h: Double = 0
        ghostty_surface_ime_point(surface, &x, &y, &w, &h)
        let viewRect = NSRect(x: x, y: frame.size.height - y, width: w, height: h)
        let winRect = convert(viewRect, to: nil)
        return window.convertToScreen(winRect)
    }

    func characterIndex(for point: NSPoint) -> Int { 0 }
}

private extension Array where Element == String {
    func uniquedPreservingOrder() -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        output.reserveCapacity(count)
        for value in self where seen.insert(value).inserted {
            output.append(value)
        }
        return output
    }
}
