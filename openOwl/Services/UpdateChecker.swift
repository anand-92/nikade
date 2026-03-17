import AppKit
import Foundation

/// Checks GitHub Releases for new versions of OpenOwl.
@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var latestVersion: String?
    @Published private(set) var downloadURL: URL?
    @Published private(set) var releaseNotes: String?
    @Published var updateAvailable = false

    private let repo = "sanvibyfish/openowl-app"
    private var hasChecked = false

    static let shared = UpdateChecker()

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Check for updates on launch (once per session, with a short delay).
    func checkOnLaunchIfNeeded() {
        guard !hasChecked else { return }
        hasChecked = true
        Task {
            try? await Task.sleep(for: .seconds(3))
            await check()
        }
    }

    /// Manually trigger an update check.
    func check() async {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let remoteVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))

            latestVersion = remoteVersion
            releaseNotes = release.body
            downloadURL = release.assets.first(where: { $0.name.hasSuffix(".dmg") })?.browserDownloadURL
                ?? release.htmlURL

            if isNewer(remote: remoteVersion, local: currentVersion) {
                updateAvailable = true
            }
        } catch {
            NSLog("UpdateChecker: failed to check — %@", error.localizedDescription)
        }
    }

    /// Open the download page in the browser.
    func openDownloadPage() {
        guard let url = downloadURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// Compare semver strings. Returns true if remote > local.
    private func isNewer(remote: String, local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }
}

// MARK: - GitHub API Models

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let body: String?
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body
        case assets
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}
