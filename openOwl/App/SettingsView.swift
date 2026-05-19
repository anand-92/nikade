import SwiftUI

// MARK: - Appearance Preference

enum AppAppearance: String, CaseIterable, Identifiable {
    case system = "system"
    case light  = "light"
    case dark   = "dark"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }

    static var current: AppAppearance {
        guard let raw = UserDefaults.standard.string(forKey: "openowl.appearance"),
              let value = AppAppearance(rawValue: raw) else { return .system }
        return value
    }

    static func apply(_ appearance: AppAppearance) {
        if appearance == .system {
            UserDefaults.standard.removeObject(forKey: "openowl.appearance")
        } else {
            UserDefaults.standard.set(appearance.rawValue, forKey: "openowl.appearance")
        }
        NSApp.appearance = appearance.nsAppearance
    }
}

// MARK: - Notification Sound

enum NotificationSound: String, CaseIterable, Identifiable {
    case none = "none"
    case basso = "Basso"
    case blow = "Blow"
    case bottle = "Bottle"
    case frog = "Frog"
    case funk = "Funk"
    case glass = "Glass"
    case hero = "Hero"
    case morse = "Morse"
    case ping = "Ping"
    case pop = "Pop"
    case purr = "Purr"
    case sosumi = "Sosumi"
    case submarine = "Submarine"
    case tink = "Tink"

    var id: String { rawValue }

    var label: String {
        self == .none ? "None" : rawValue
    }

    static let defaultsKey = "openowl.notificationSound"

    static var current: NotificationSound {
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
              let value = NotificationSound(rawValue: raw) else { return .submarine }
        return value
    }

    static func apply(_ sound: NotificationSound) {
        UserDefaults.standard.set(sound.rawValue, forKey: defaultsKey)
    }

    /// Play the sound. Returns immediately if set to .none.
    func play() {
        guard self != .none else { return }
        let path = "/System/Library/Sounds/\(rawValue).aiff"
        NSSound(contentsOfFile: path, byReference: true)?.play()
    }
}

// MARK: - Settings View

struct TerminalTheme: Identifiable, Equatable {
    enum Source {
        case openOwl
        case ghostty
    }

    let name: String
    let configValue: String
    let source: Source

    var id: String { configValue }

    var label: String {
        switch source {
        case .openOwl: return "\(name) (OpenOwl)"
        case .ghostty: return name
        }
    }
}

struct SettingsView: View {
    @State private var appearance: AppAppearance = .current
    @State private var terminalThemeValue: String = GhosttyConfig.readOverride(key: "theme")
        ?? GhosttyConfig.openOwlNeonThemeValue
        ?? ""
    @State private var themeSearchQuery = ""
    @State private var showRestartHint = false
    @State private var notificationSound: NotificationSound = .current

    private var availableThemes: [TerminalTheme] {
        let themes = Self.loadThemeList()
        if themeSearchQuery.isEmpty { return themes }
        return themes.filter { $0.label.localizedCaseInsensitiveContains(themeSearchQuery) }
    }

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Window Mode", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Label(option.label, systemImage: option.icon)
                            .tag(option)
                    }
                }
                .pickerStyle(.inline)
                .onChange(of: appearance) { _, newValue in
                    AppAppearance.apply(newValue)
                }
            }

            Section("Notifications") {
                Picker("Alert Sound", selection: $notificationSound) {
                    ForEach(NotificationSound.allCases) { sound in
                        Text(sound.label).tag(sound)
                    }
                }
                .onChange(of: notificationSound) { _, newValue in
                    NotificationSound.apply(newValue)
                    newValue.play()
                }
            }

            Section("Terminal Theme") {
                TextField("Search themes...", text: $themeSearchQuery)
                    .textFieldStyle(.roundedBorder)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(availableThemes) { theme in
                            Button {
                                terminalThemeValue = theme.configValue
                            } label: {
                                Text(theme.label)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(terminalThemeValue == theme.configValue ? Color.accentColor : Color.clear)
                                    .foregroundStyle(terminalThemeValue == theme.configValue ? .white : .primary)
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                }
                .frame(height: 200)
                .background(AppPalette.surface)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5)
                )
                .onChange(of: terminalThemeValue) { _, newValue in
                    guard !newValue.isEmpty else { return }
                    GhosttyConfig.setOverride(key: "theme", value: newValue)
                    showRestartHint = true
                }

                if showRestartHint {
                    Label("Restart app to apply theme change", systemImage: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 500)
    }

    private static func loadThemeList() -> [TerminalTheme] {
        GhosttyConfig.installFirstPartyThemes()

        let firstPartyThemes = GhosttyConfig.openOwlNeonThemeValue.map {
            [
                TerminalTheme(
                    name: GhosttyConfig.openOwlNeonThemeName,
                    configValue: $0,
                    source: .openOwl
                )
            ]
        } ?? []

        // Find themes directory in ghostty resources
        guard let resourcesDir = ProcessInfo.processInfo.environment["GHOSTTY_RESOURCES_DIR"] else {
            return firstPartyThemes
        }
        let themesDir = URL(fileURLWithPath: resourcesDir).appendingPathComponent("themes")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: themesDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return firstPartyThemes }

        let ghosttyThemes = files
            .map { $0.lastPathComponent }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .filter { $0 != GhosttyConfig.openOwlNeonThemeName }
            .map { TerminalTheme(name: $0, configValue: $0, source: .ghostty) }

        return firstPartyThemes + ghosttyThemes
    }
}
