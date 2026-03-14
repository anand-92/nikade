import AppKit

/// Converts NSEvent modifier flags to ghostty_input_mods_e bitmask.
enum GhosttyInput {
    static func eventModifierFlags(mods: ghostty_input_mods_e) -> NSEvent.ModifierFlags {
        var flags = NSEvent.ModifierFlags()

        if mods.rawValue & GHOSTTY_MODS_SHIFT.rawValue != 0 {
            flags.insert(.shift)
        }
        if mods.rawValue & GHOSTTY_MODS_CTRL.rawValue != 0 {
            flags.insert(.control)
        }
        if mods.rawValue & GHOSTTY_MODS_ALT.rawValue != 0 {
            flags.insert(.option)
        }
        if mods.rawValue & GHOSTTY_MODS_SUPER.rawValue != 0 {
            flags.insert(.command)
        }
        if mods.rawValue & GHOSTTY_MODS_CAPS.rawValue != 0 {
            flags.insert(.capsLock)
        }

        return flags
    }

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
    static func keyEvent(
        from event: NSEvent,
        action: ghostty_input_action_e,
        translationMods: NSEvent.ModifierFlags? = nil
    ) -> ghostty_input_key_s {
        var key = ghostty_input_key_s()
        key.action = action
        key.keycode = UInt32(event.keyCode)
        key.mods = ghosttyMods(event.modifierFlags)
        let consumedFlags = translationMods ?? event.modifierFlags
        var consumedMods = GHOSTTY_MODS_NONE.rawValue
        // Match cmux: only Shift/Option are considered text-translation modifiers.
        if consumedFlags.contains(.shift) {
            consumedMods |= GHOSTTY_MODS_SHIFT.rawValue
        }
        if consumedFlags.contains(.option) {
            consumedMods |= GHOSTTY_MODS_ALT.rawValue
        }
        key.consumed_mods = ghostty_input_mods_e(consumedMods)
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

    static func ghosttyCharacters(from event: NSEvent) -> String? {
        guard let characters = event.characters else { return nil }

        if characters.count == 1,
           let scalar = characters.unicodeScalars.first {
            // Let Ghostty key encoder handle control character generation.
            if scalar.value < 0x20 {
                return event.characters(byApplyingModifiers: event.modifierFlags.subtracting(.control))
            }

            // Match cmux workaround: Shift+` may arrive as ESC from AppKit.
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if scalar.value == 0x1B,
               flags == [.shift],
               event.charactersIgnoringModifiers == "`" {
                return "~"
            }

            // Skip PUA function key codepoints.
            if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
                return nil
            }
        }

        return characters
    }
}
