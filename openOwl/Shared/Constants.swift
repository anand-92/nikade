import Foundation

// #region agent log
func installExitTracing() {
    atexit {
        debugLog("atexit", "atexit handler called - app is exiting", [:])
    }
    signal(SIGABRT) { sig in
        debugLog("signal", "SIGABRT caught", ["signal": sig])
    }
    signal(SIGTERM) { sig in
        debugLog("signal", "SIGTERM caught", ["signal": sig])
    }
}

func debugLog(_ location: String, _ message: String, _ data: [String: Any] = [:]) {
    let logPath = "/Users/sanvi/Documents/workspace/ios/openowl-app/.cursor/debug-c6da11.log"
    let timestamp = Int(Date().timeIntervalSince1970 * 1000)
    var payload: [String: Any] = [
        "sessionId": "c6da11",
        "location": location,
        "message": message,
        "timestamp": timestamp
    ]
    if !data.isEmpty { payload["data"] = data }
    guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
          var line = String(data: jsonData, encoding: .utf8) else { return }
    line += "\n"
    let fm = FileManager.default
    if fm.fileExists(atPath: logPath) {
        if let fh = FileHandle(forWritingAtPath: logPath) {
            fh.seekToEndOfFile()
            fh.write(line.data(using: .utf8)!)
            fh.closeFile()
        }
    } else {
        fm.createFile(atPath: logPath, contents: line.data(using: .utf8))
    }
}
// #endregion

enum AppConstants {
    static let appName = "openOwl"
    static let bundleIdentifier = "com.openowl.app"

    // Ghostty
    static let termEnv = "xterm-ghostty"
    static let ghosttyResourcesDirEnv = "GHOSTTY_RESOURCES_DIR"

    // Layout
    static let sidebarMinWidth: CGFloat = 200
    static let sidebarIdealWidth: CGFloat = 250
    static let contentMinWidth: CGFloat = 400
    static let windowMinWidth: CGFloat = 800
    static let windowMinHeight: CGFloat = 500
}
