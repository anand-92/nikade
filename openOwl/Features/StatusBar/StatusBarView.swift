import SwiftUI

/// 底部状态栏，参照 CodeEdit 的 StatusBarView。
/// 28pt 高度，左侧 Git branch + 文件变更数，右侧文件/终端信息。
struct StatusBarView: View {
    @EnvironmentObject private var gitStore: GitChangesStore
    @EnvironmentObject private var navigationStore: AppNavigationStore
    @EnvironmentObject private var projectStore: ProjectStore
    @EnvironmentObject private var fileExplorerStore: FileExplorerStore

    static let height: CGFloat = AppSpacing.statusBarHeight

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // 左侧：Git branch + dirty indicator
            StatusBarBranchLabel(
                branch: gitStore.statusSnapshot?.branch,
                changesCount: totalChangesCount
            )

            Spacer()

            // 右侧：根据当前 tab 显示不同信息
            StatusBarContextInfo(
                activeTab: navigationStore.activeTab,
                selectedFileName: fileExplorerStore.selectedNode?.name,
                terminalPaneCount: nil
            )
        }
        .padding(.horizontal, 10)
        .padding(.top, 1)
        .frame(height: Self.height)
        .background(.bar)
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
                .font(.system(size: 10))
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

private struct StatusBarContextInfo: View {
    let activeTab: ViewTab
    let selectedFileName: String?
    let terminalPaneCount: Int?

    var body: some View {
        HStack(spacing: 6) {
            switch activeTab {
            case .terminal:
                Image(systemName: "terminal")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text("Terminal")
                    .font(AppFonts.statusBar)
                    .foregroundStyle(.tertiary)

            case .gitChanges:
                Image(systemName: "arrow.triangle.pull")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text("Git")
                    .font(AppFonts.statusBar)
                    .foregroundStyle(.tertiary)

            case .fileExplorer:
                if let name = selectedFileName {
                    Image(systemName: "doc")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text(name)
                        .font(AppFonts.statusBar)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
    }
}
