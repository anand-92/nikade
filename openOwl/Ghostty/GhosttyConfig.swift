import Foundation

struct GhosttyConfigSnapshot {
    let command: String?
    let fontFamily: String?
    let fontSize: Double?
    let theme: String?
    let scrollbackLimit: UInt?
}

/// Manages ghostty_config_t lifecycle.
/// Loads user's ~/.config/ghostty/config and finalizes for use.
final class GhosttyConfig {
    private(set) var config: ghostty_config_t?
    private(set) var diagnostics: [String] = []
    private(set) var snapshot = GhosttyConfigSnapshot(
        command: nil,
        fontFamily: nil,
        fontSize: nil,
        theme: nil,
        scrollbackLimit: nil
    )

    init() {
        config = ghostty_config_new()
        guard config != nil else { return }

        // Load user's default config files (~/.config/ghostty/config)
        ghostty_config_load_default_files(config)
        ghostty_config_load_recursive_files(config)
        ghostty_config_finalize(config)

        diagnostics = Self.collectDiagnostics(from: config)
        snapshot = Self.captureSnapshot(from: config)

        if !diagnostics.isEmpty {
            NSLog("openOwl: ghostty config diagnostics count = \(diagnostics.count)")
            for diagnostic in diagnostics {
                NSLog("openOwl: ghostty config diagnostic: \(diagnostic)")
            }
        }

        NSLog(
            "openOwl: config snapshot command=%@ font-family=%@ font-size=%@ theme=%@ scrollback-limit=%@",
            snapshot.command ?? "<nil>",
            snapshot.fontFamily ?? "<nil>",
            snapshot.fontSize.map { String($0) } ?? "<nil>",
            snapshot.theme ?? "<nil>",
            snapshot.scrollbackLimit.map { String($0) } ?? "<nil>"
        )
    }

    deinit {
        if let config {
            ghostty_config_free(config)
        }
    }
}

private extension GhosttyConfig {
    static func collectDiagnostics(from config: ghostty_config_t?) -> [String] {
        guard let config else { return [] }
        let count = ghostty_config_diagnostics_count(config)
        guard count > 0 else { return [] }

        var output: [String] = []
        output.reserveCapacity(Int(count))

        for index in 0..<count {
            let diagnostic = ghostty_config_get_diagnostic(config, index)
            output.append(String(cString: diagnostic.message))
        }
        return output
    }

    static func captureSnapshot(from config: ghostty_config_t?) -> GhosttyConfigSnapshot {
        GhosttyConfigSnapshot(
            command: readString(config: config, key: "command"),
            fontFamily: readString(config: config, key: "font-family"),
            fontSize: readFontSize(config: config, key: "font-size"),
            theme: readString(config: config, key: "theme"),
            scrollbackLimit: readUInt(config: config, key: "scrollback-limit")
        )
    }

    static func readString(config: ghostty_config_t?, key: String) -> String? {
        guard let config else { return nil }
        var value: UnsafePointer<CChar>?
        guard ghostty_config_get(config, &value, key, UInt(key.utf8.count)) else { return nil }
        guard let value else { return nil }
        let string = String(cString: value)
        return string.isEmpty ? nil : string
    }

    static func readFontSize(config: ghostty_config_t?, key: String) -> Double? {
        guard let config else { return nil }
        var value: Float = 0
        guard ghostty_config_get(config, &value, key, UInt(key.utf8.count)) else { return nil }
        guard value.isFinite, value > 0 else { return nil }
        return Double(value)
    }

    static func readUInt(config: ghostty_config_t?, key: String) -> UInt? {
        guard let config else { return nil }
        var value: UInt64 = 0
        guard ghostty_config_get(config, &value, key, UInt(key.utf8.count)) else { return nil }
        return UInt(value)
    }
}
