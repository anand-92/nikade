import AppKit
import Foundation
import Observation

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

// MARK: - Claude Status (RSS)

enum ClaudeServiceState: Equatable {
    case checking
    case normal
    case abnormal
}

struct ClaudeIncident: Equatable {
    let title: String
    let latestStatus: String
    let link: URL?
    let publishedAt: Date?

    var isResolved: Bool {
        latestStatus
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("Resolved") == .orderedSame
    }
}

struct ClaudeStatusSnapshot: Equatable {
    let state: ClaudeServiceState
    let headline: String
    let incidentURL: URL?
    let lastUpdatedAt: Date?
    let bannerVisible: Bool
}

@MainActor
@Observable
final class ClaudeStatusStore {
    private(set) var state: ClaudeServiceState = .checking
    private(set) var headline: String = "Fetching status..."
    private(set) var incidentURL: URL?
    private(set) var lastUpdatedAt: Date?
    private(set) var activeIncident: ClaudeIncident?

    let statusPageURL = URL(string: "https://status.claude.com")!

    private let historyURL = URL(string: "https://status.claude.com/history.rss")!
    private let defaults: UserDefaults
    private var pollingTask: Task<Void, Never>?
    private var hasStarted = false
    private var dismissedIncidentKeys: Set<String> = []

    private static let dismissedIncidentsDefaultsKey = "openowl.claudeStatus.dismissedIncidentKeys"

    init() {
        self.defaults = .standard
        if let stored = defaults.array(forKey: Self.dismissedIncidentsDefaultsKey) as? [String] {
            dismissedIncidentKeys = Set(stored)
        }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        if let stored = defaults.array(forKey: Self.dismissedIncidentsDefaultsKey) as? [String] {
            dismissedIncidentKeys = Set(stored)
        }
    }

    var snapshot: ClaudeStatusSnapshot {
        ClaudeStatusSnapshot(
            state: state,
            headline: headline,
            incidentURL: incidentURL,
            lastUpdatedAt: lastUpdatedAt,
            bannerVisible: shouldShowIncidentBanner
        )
    }

    var shouldShowIncidentBanner: Bool {
        state == .abnormal && activeIncident != nil
    }

    var bannerTitle: String {
        activeIncident?.title ?? headline
    }

    var bannerIncidentURL: URL {
        activeIncident?.link ?? statusPageURL
    }

    /// Start polling immediately, then refresh every 5 minutes.
    func startPollingIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true

        pollingTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshNow()

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                if Task.isCancelled { break }
                await self.refreshNow()
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        hasStarted = false
    }

    /// Fetch and parse RSS. On failure, keep current UI state unchanged.
    func refreshNow() async {
        var request = URLRequest(url: historyURL)
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            let incidents = ClaudeStatusRSSParser.parse(data: data)
            applyRefreshResult(incidents)
        } catch {
            NSLog("ClaudeStatusStore: failed to refresh — %@", error.localizedDescription)
        }
    }

    /// Internal for testability.
    func applyRefreshResult(_ incidents: [ClaudeIncident]?) {
        guard let incidents else { return } // Failure/no data => no-op by product decision.

        let unresolved = incidents
            .filter { !$0.isResolved }
            .sorted(by: Self.sortByPublishedAtDesc)

        if let latest = unresolved.first {
            state = .abnormal
            headline = latest.title
            incidentURL = latest.link

            // Show banner only for incidents the user has not dismissed.
            activeIncident = unresolved.first { incident in
                !dismissedIncidentKeys.contains(incident.incidentKey)
            }
        } else {
            state = .normal
            headline = "All systems operational"
            incidentURL = nil
            activeIncident = nil
        }
        lastUpdatedAt = Date()
    }

    func dismissCurrentIncident() {
        guard let incident = activeIncident else { return }
        dismissedIncidentKeys.insert(incident.incidentKey)
        persistDismissedIncidentKeys()
        activeIncident = nil
    }

    private func persistDismissedIncidentKeys() {
        let maxItems = 256
        if dismissedIncidentKeys.count > maxItems {
            dismissedIncidentKeys = Set(dismissedIncidentKeys.prefix(maxItems))
        }
        defaults.set(Array(dismissedIncidentKeys), forKey: Self.dismissedIncidentsDefaultsKey)
    }

    private static func sortByPublishedAtDesc(_ lhs: ClaudeIncident, _ rhs: ClaudeIncident) -> Bool {
        switch (lhs.publishedAt, rhs.publishedAt) {
        case let (l?, r?):
            return l > r
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return false
        }
    }
}

private extension ClaudeIncident {
    var incidentKey: String {
        if let link {
            return link.absoluteString
        }
        if let publishedAt {
            return "\(title)|\(publishedAt.timeIntervalSince1970)"
        }
        return title
    }
}

enum ClaudeStatusRSSParser {
    private static let pubDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter
    }()

    static func parse(data: Data) -> [ClaudeIncident]? {
        let xmlParser = XMLParser(data: data)
        let delegate = ClaudeStatusRSSDelegate()
        xmlParser.delegate = delegate

        guard xmlParser.parse() else { return nil }

        return delegate.items.compactMap { item in
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }

            let decodedDescription = item.description.decodingHTMLEntities()
            let status = decodedDescription.firstStrongText() ?? "Unknown"
            let link = URL(string: item.link.trimmingCharacters(in: .whitespacesAndNewlines))
            let publishedAt = pubDateFormatter.date(from: item.pubDate.trimmingCharacters(in: .whitespacesAndNewlines))

            return ClaudeIncident(
                title: title,
                latestStatus: status,
                link: link,
                publishedAt: publishedAt
            )
        }
    }
}

private struct ClaudeRSSItem {
    var title = ""
    var description = ""
    var link = ""
    var pubDate = ""
}

private final class ClaudeStatusRSSDelegate: NSObject, XMLParserDelegate {
    private static let trackedFields: Set<String> = ["title", "description", "link", "pubDate"]

    private(set) var items: [ClaudeRSSItem] = []

    private var currentItem: ClaudeRSSItem?
    private var activeField: String?
    private var fieldBuffer = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "item" {
            currentItem = ClaudeRSSItem()
            activeField = nil
            fieldBuffer = ""
            return
        }

        guard currentItem != nil else { return }
        if Self.trackedFields.contains(elementName) {
            activeField = elementName
            fieldBuffer = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard currentItem != nil, activeField != nil else { return }
        fieldBuffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard var item = currentItem else { return }

        if let activeField, activeField == elementName {
            switch activeField {
            case "title":
                item.title += fieldBuffer
            case "description":
                item.description += fieldBuffer
            case "link":
                item.link += fieldBuffer
            case "pubDate":
                item.pubDate += fieldBuffer
            default:
                break
            }
            currentItem = item
            self.activeField = nil
            fieldBuffer = ""
        } else {
            currentItem = item
        }

        if elementName == "item" {
            items.append(item)
            currentItem = nil
            self.activeField = nil
            fieldBuffer = ""
        }
    }
}

private extension String {
    func decodingHTMLEntities() -> String {
        var output = self
        let entities: [(String, String)] = [
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&amp;", "&"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'")
        ]

        for (entity, replacement) in entities {
            output = output.replacingOccurrences(of: entity, with: replacement)
        }
        return output
    }

    func firstStrongText() -> String? {
        let pattern = #"<strong>\s*([^<]+?)\s*</strong>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let nsString = self as NSString
        let searchRange = NSRange(location: 0, length: nsString.length)
        guard let match = regex.firstMatch(in: self, options: [], range: searchRange),
              match.numberOfRanges > 1 else {
            return nil
        }

        let statusRange = match.range(at: 1)
        guard statusRange.location != NSNotFound else { return nil }

        return nsString.substring(with: statusRange)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
