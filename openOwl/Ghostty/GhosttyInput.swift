import AppKit

/// Converts NSEvent modifier flags to ghostty_input_mods_e bitmask.
enum GhosttyInput {
    static func modifierFlags(from event: NSEvent) -> ghostty_input_mods_e {
        var mods = GHOSTTY_MODS_NONE.rawValue
        let flags = event.modifierFlags

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
    static func keyEvent(from event: NSEvent, action: ghostty_input_action_e) -> ghostty_input_key_s {
        let mods = modifierFlags(from: event)
        let keycode = UInt32(event.keyCode)
        let text = event.characters ?? ""

        var key = ghostty_input_key_s()
        key.action = action
        key.mods = mods
        key.consumed_mods = GHOSTTY_MODS_NONE
        key.keycode = keycode
        key.text = (text as NSString).utf8String
        key.unshifted_codepoint = 0
        key.composing = false

        return key
    }
}
