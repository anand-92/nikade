import Testing
import Foundation
@testable import openOwl

@Suite("ProjectStore Helpers")
struct ProjectStoreHelpersTests {

    // MARK: - ProjectItem

    @Test func projectItem_urlFromPath() {
        let item = ProjectItem(url: URL(fileURLWithPath: "/Users/dev/project"))
        #expect(item.url.path == "/Users/dev/project")
        #expect(item.displayName == "project")
    }

    @Test func projectItem_isWorktree() {
        var item = ProjectItem(
            path: "/tmp/wt",
            name: "feature",
            worktreeOf: "parent-id",
            worktreeBranch: "feature/x"
        )
        #expect(item.isWorktree == true)

        item = ProjectItem(url: URL(fileURLWithPath: "/tmp/project"))
        #expect(item.isWorktree == false)
    }

    // MARK: - GitServiceError

    @Test func gitServiceError_descriptions() {
        let notGit = GitServiceError.notGitRepository
        #expect(notGit.errorDescription?.contains("not a Git repository") == true)

        let failed = GitServiceError.commandFailed(command: "git push", exitCode: 1, stderr: "rejected")
        #expect(failed.errorDescription?.contains("git push") == true)
        #expect(failed.errorDescription?.contains("rejected") == true)

        let invalid = GitServiceError.invalidCommitMessage
        #expect(invalid.errorDescription?.contains("empty") == true)
    }

    @Test func gitServiceError_emptyStderr() {
        let err = GitServiceError.commandFailed(command: "git pull", exitCode: 128, stderr: "")
        #expect(err.errorDescription?.contains("Unknown git error") == true)
    }

    // MARK: - GitFileChange

    @Test func gitFileChange_id_uniquePerSection() {
        let staged = GitFileChange(path: "file.swift", indexStatus: "M", workTreeStatus: " ", section: .staged)
        let modified = GitFileChange(path: "file.swift", indexStatus: " ", workTreeStatus: "M", section: .modified)
        #expect(staged.id != modified.id)
    }

    @Test func gitFileChange_statusCode() {
        let change = GitFileChange(path: "file.swift", indexStatus: "A", workTreeStatus: "M", section: .staged)
        #expect(change.statusCode == "AM")
    }

    // MARK: - GitStatusSnapshot

    @Test func gitStatusSnapshot_hasAnyChanges() {
        let empty = GitStatusSnapshot(
            repositoryRoot: URL(fileURLWithPath: "/tmp"),
            branch: "main", upstreamBranch: nil, branchTrackingStatus: nil,
            aheadCount: 0, behindCount: 0,
            staged: [], modified: [], untracked: [], untrackedTruncated: false
        )
        #expect(empty.hasAnyChanges == false)
        #expect(empty.hasStagedChanges == false)

        let withStaged = GitStatusSnapshot(
            repositoryRoot: URL(fileURLWithPath: "/tmp"),
            branch: "main", upstreamBranch: nil, branchTrackingStatus: nil,
            aheadCount: 0, behindCount: 0,
            staged: [GitFileChange(path: "a", indexStatus: "A", workTreeStatus: " ", section: .staged)],
            modified: [], untracked: [], untrackedTruncated: false
        )
        #expect(withStaged.hasAnyChanges == true)
        #expect(withStaged.hasStagedChanges == true)
    }
}

@Suite("Claude Status RSS")
struct ClaudeStatusRSSTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "openowl.tests.claude-status.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func rssParser_extractsFirstStrongStatus() throws {
        let rss = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <item>
              <title>Elevated errors on Claude Opus 4.6</title>
              <description>
        &lt;p&gt;&lt;small&gt;Mar 17&lt;/small&gt;&lt;br&gt;&lt;strong&gt;Monitoring&lt;/strong&gt; - A fix has been implemented.&lt;/p&gt;&lt;p&gt;&lt;small&gt;Mar 17&lt;/small&gt;&lt;br&gt;&lt;strong&gt;Identified&lt;/strong&gt; - The issue has been identified.&lt;/p&gt;
              </description>
              <pubDate>Tue, 17 Mar 2026 20:02:43 +0000</pubDate>
              <link>https://status.claude.com/incidents/mhnzmndv58bt</link>
            </item>
          </channel>
        </rss>
        """

        let incidents = ClaudeStatusRSSParser.parse(data: Data(rss.utf8))
        #expect(incidents?.count == 1)
        #expect(incidents?.first?.title == "Elevated errors on Claude Opus 4.6")
        #expect(incidents?.first?.latestStatus == "Monitoring")
        #expect(incidents?.first?.link?.absoluteString == "https://status.claude.com/incidents/mhnzmndv58bt")
    }

    @Test @MainActor func store_abnormalWhenUnresolvedExists() {
        let store = ClaudeStatusStore(defaults: makeDefaults())

        let resolved = ClaudeIncident(
            title: "Resolved incident",
            latestStatus: "Resolved",
            link: URL(string: "https://status.claude.com/incidents/resolved"),
            publishedAt: Date(timeIntervalSince1970: 100)
        )
        let unresolvedOld = ClaudeIncident(
            title: "Older unresolved",
            latestStatus: "Identified",
            link: URL(string: "https://status.claude.com/incidents/old"),
            publishedAt: Date(timeIntervalSince1970: 200)
        )
        let unresolvedNew = ClaudeIncident(
            title: "Newest unresolved",
            latestStatus: "Monitoring",
            link: URL(string: "https://status.claude.com/incidents/new"),
            publishedAt: Date(timeIntervalSince1970: 300)
        )

        store.applyRefreshResult([resolved, unresolvedOld, unresolvedNew])

        #expect(store.state == .abnormal)
        #expect(store.headline == "Newest unresolved")
        #expect(store.incidentURL?.absoluteString == "https://status.claude.com/incidents/new")
        #expect(store.shouldShowIncidentBanner == true)
        #expect(store.lastUpdatedAt != nil)
    }

    @Test @MainActor func store_normalWhenAllResolved() {
        let store = ClaudeStatusStore(defaults: makeDefaults())

        let first = ClaudeIncident(
            title: "Incident A",
            latestStatus: "Resolved",
            link: URL(string: "https://status.claude.com/incidents/a"),
            publishedAt: Date(timeIntervalSince1970: 100)
        )
        let second = ClaudeIncident(
            title: "Incident B",
            latestStatus: "Resolved",
            link: URL(string: "https://status.claude.com/incidents/b"),
            publishedAt: Date(timeIntervalSince1970: 200)
        )

        store.applyRefreshResult([first, second])

        #expect(store.state == .normal)
        #expect(store.headline == "All systems operational")
        #expect(store.incidentURL == nil)
        #expect(store.shouldShowIncidentBanner == false)
    }

    @Test @MainActor func store_failureNoOp_keepsPreviousSnapshot() {
        let store = ClaudeStatusStore(defaults: makeDefaults())

        let unresolved = ClaudeIncident(
            title: "Incident still open",
            latestStatus: "Monitoring",
            link: URL(string: "https://status.claude.com/incidents/open"),
            publishedAt: Date(timeIntervalSince1970: 100)
        )
        store.applyRefreshResult([unresolved])
        let before = store.snapshot

        store.applyRefreshResult(nil) // Failed refresh should not disturb UI state.
        let after = store.snapshot

        #expect(after == before)
    }

    @Test @MainActor func store_initialState_isChecking() {
        let store = ClaudeStatusStore(defaults: makeDefaults())
        #expect(store.state == .checking)
        #expect(store.headline == "Fetching status...")
        #expect(store.lastUpdatedAt == nil)
        #expect(store.shouldShowIncidentBanner == false)
    }

    @Test @MainActor func dismissCurrentIncident_hidesBannerForSameIncident() {
        let defaults = makeDefaults()
        let store = ClaudeStatusStore(defaults: defaults)

        let incident = ClaudeIncident(
            title: "Incident A",
            latestStatus: "Monitoring",
            link: URL(string: "https://status.claude.com/incidents/a"),
            publishedAt: Date(timeIntervalSince1970: 100)
        )

        store.applyRefreshResult([incident])
        #expect(store.shouldShowIncidentBanner == true)

        store.dismissCurrentIncident()
        #expect(store.shouldShowIncidentBanner == false)

        // Same incident should remain dismissed after refresh.
        store.applyRefreshResult([incident])
        #expect(store.shouldShowIncidentBanner == false)
    }

    @Test @MainActor func dismissedIncident_doesNotBlockNewIncident() {
        let defaults = makeDefaults()
        let store = ClaudeStatusStore(defaults: defaults)

        let incidentA = ClaudeIncident(
            title: "Incident A",
            latestStatus: "Monitoring",
            link: URL(string: "https://status.claude.com/incidents/a"),
            publishedAt: Date(timeIntervalSince1970: 100)
        )
        let incidentB = ClaudeIncident(
            title: "Incident B",
            latestStatus: "Identified",
            link: URL(string: "https://status.claude.com/incidents/b"),
            publishedAt: Date(timeIntervalSince1970: 200)
        )

        store.applyRefreshResult([incidentA])
        store.dismissCurrentIncident()
        #expect(store.shouldShowIncidentBanner == false)

        // New incident should show again.
        store.applyRefreshResult([incidentB])
        #expect(store.shouldShowIncidentBanner == true)
        #expect(store.bannerTitle == "Incident B")
    }
}
