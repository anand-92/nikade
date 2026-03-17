import SwiftUI

/// Menu bar button that triggers update check and opens the update window.
struct CheckForUpdatesButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Check for Updates...") {
            Task {
                await UpdateChecker.shared.check()
                openWindow(id: "update")
            }
        }
    }
}

struct UpdateAlertView: View {
    @ObservedObject private var checker = UpdateChecker.shared

    var body: some View {
        VStack(spacing: 16) {
            Group {
                if let icon = NSApp?.applicationIconImage {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "app.fill").resizable()
                }
            }
            .frame(width: 64, height: 64)

            if checker.updateAvailable, let version = checker.latestVersion {
                Text("OpenOwl \(version) Available")
                    .font(.headline)

                Text("You are currently on version \(checker.currentVersion).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let notes = checker.releaseNotes, !notes.isEmpty {
                    ScrollView {
                        Text(notes)
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                HStack(spacing: 12) {
                    Button("Later") {
                        NSApp.keyWindow?.close()
                    }

                    Button("Download") {
                        checker.openDownloadPage()
                        NSApp.keyWindow?.close()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            } else {
                Text("You're up to date!")
                    .font(.headline)

                Text("OpenOwl \(checker.currentVersion) is the latest version.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button("OK") {
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}
