import SwiftUI

/// 底部状态栏，参照 CodeEdit 的 StatusBarView。
/// 28pt 高度，左侧 Git branch + 文件变更数，右侧文件/终端信息。
struct StatusBarView: View {
    @Environment(GitChangesStore.self) private var gitStore
    @Environment(RightDockStore.self) private var rightDockStore
    @Environment(ProjectStore.self) private var projectStore
    @Environment(FileExplorerStore.self) private var fileExplorerStore

    static let height: CGFloat = AppSpacing.statusBarHeight

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // 左侧：Git branch + dirty indicator
            StatusBarBranchLabel(
                branch: gitStore.statusSnapshot?.branch,
                changesCount: totalChangesCount
            )

            Spacer()

            #if DEBUG
            MetalStatsView()
            #endif

            // 右侧：根据当前可见区域显示不同信息
            StatusBarContextInfo(
                visibleArea: visibleArea,
                selectedFileName: fileExplorerStore.selectedNode?.name
            )
        }
        .padding(.horizontal, 10)
        .padding(.top, 1)
        .frame(height: Self.height)
        .background(.bar)
    }

    private var visibleArea: StatusBarVisibleArea {
        guard rightDockStore.isExpanded else { return .terminal }
        switch rightDockStore.activeTab {
        case .files: return .files
        case .git: return .git
        case .deploy: return .deploy
        }
    }

    private var totalChangesCount: Int {
        guard let snapshot = gitStore.statusSnapshot else { return 0 }
        return snapshot.staged.count
            + snapshot.modified.count
            + snapshot.untracked.count
    }
}

// MARK: - Branch Label

private struct StatusBarBranchLabel: View {
    let branch: String?
    let changesCount: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.branch")
                .font(AppFonts.toolbarIcon)
                .foregroundStyle(.secondary)

            Text(branch ?? "—")
                .font(AppFonts.statusBar)
                .lineLimit(1)
                .foregroundStyle(.secondary)

            if changesCount > 0 {
                Text("\(changesCount)")
                    .font(AppFonts.badge)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
    }
}

// MARK: - Context Info (右侧)

enum StatusBarVisibleArea {
    case terminal
    case git
    case files
    case deploy
}

private struct StatusBarContextInfo: View {
    let visibleArea: StatusBarVisibleArea
    let selectedFileName: String?

    var body: some View {
        HStack(spacing: 6) {
            switch visibleArea {
            case .terminal:
                Image(systemName: "terminal")
                    .font(AppFonts.toolbarIcon)
                    .foregroundStyle(.tertiary)
                Text("Terminal")
                    .font(AppFonts.statusBar)
                    .foregroundStyle(.tertiary)

            case .git:
                Image(systemName: "arrow.triangle.pull")
                    .font(AppFonts.toolbarIcon)
                    .foregroundStyle(.tertiary)
                Text("Git")
                    .font(AppFonts.statusBar)
                    .foregroundStyle(.tertiary)

            case .files:
                if let name = selectedFileName {
                    Image(systemName: "doc")
                        .font(AppFonts.toolbarIcon)
                        .foregroundStyle(.tertiary)
                    Text(name)
                        .font(AppFonts.statusBar)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

            case .deploy:
                Image(systemName: "shippingbox")
                    .font(AppFonts.toolbarIcon)
                    .foregroundStyle(.tertiary)
                Text("Deploy")
                    .font(AppFonts.statusBar)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Metal Stats (DEBUG only)

#if DEBUG
private struct MetalStatsView: View {
    @Environment(GhosttyAppManager.self) private var manager
    @State private var total = 0
    @State private var active = 0

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(active <= 1 ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            Text("Metal \(active)/\(total)")
                .font(Font.system(.caption, design: .monospaced))
        }
        .foregroundStyle(.tertiary)
        .help("Active/Total Metal surfaces (ideal: 1 active)")
        .onAppear { refresh() }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            refresh()
        }
    }

    private func refresh() {
        let stats = manager.surfaceStats
        total = stats.total
        active = stats.active
    }
}
#endif
