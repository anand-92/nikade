import Foundation

/// Manages ghostty_config_t lifecycle.
/// Loads user's ~/.config/ghostty/config and finalizes for use.
final class GhosttyConfig {
    private(set) var config: ghostty_config_t?

    init() {
        config = ghostty_config_new()
        guard config != nil else { return }

        // Load user's default config files (~/.config/ghostty/config)
        ghostty_config_load_default_files(config)
        ghostty_config_finalize(config)
    }

    deinit {
        if let config {
            ghostty_config_free(config)
        }
    }
}
