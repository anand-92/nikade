import AppKit

/// Converts NSEvent modifier flags to ghostty_input_mods_e bitmask.
enum GhosttyInput {
    static func modifierFlags(from event: NSEvent) -> ghostty_input_mods_e {
        ghosttyMods(event.modifierFlags)
    }

    static func ghosttyMods(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var mods = GHOSTTY_MODS_NONE.rawValue

        if flags.contains(.shift) {
            mods |= GHOSTTY_MODS_SHIFT.rawValue
        }
        if flags.contains(.control) {
            mods |= GHOSTTY_MODS_CTRL.rawValue
        }
        if flags.contains(.option) {
            mods |= GHOSTTY_MODS_ALT.rawValue
        }
        if flags.contains(.command) {
            mods |= GHOSTTY_MODS_SUPER.rawValue
        }
        if flags.contains(.capsLock) {
            mods |= GHOSTTY_MODS_CAPS.rawValue
        }

        return ghostty_input_mods_e(mods)
    }

    /// Build a ghostty_input_key_s from an NSEvent.
    /// Following Ghostty's approach: text is NOT read here (caller must set it).
    /// This prevents crashes from accessing .characters on FlagsChanged events.
    static func keyEvent(from event: NSEvent, action: ghostty_input_action_e) -> ghostty_input_key_s {
        var key = ghostty_input_key_s()
        key.action = action
        key.keycode = UInt32(event.keyCode)
        key.mods = ghosttyMods(event.modifierFlags)
        key.consumed_mods = GHOSTTY_MODS_NONE
        key.text = nil
        key.composing = false
        key.unshifted_codepoint = 0

        // Only read character data for actual key events, never for flagsChanged
        if event.type == .keyDown || event.type == .keyUp {
            if let chars = event.characters(byApplyingModifiers: []),
               let codepoint = chars.unicodeScalars.first {
                key.unshifted_codepoint = codepoint.value
            }
        }

        return key
    }
}
