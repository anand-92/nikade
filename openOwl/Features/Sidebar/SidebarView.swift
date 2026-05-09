import SwiftUI

struct SidebarView: View {
    @Environment(ProjectStore.self) private var projectStore
    @Environment(ClaudeStatusStore.self) private var claudeStatusStore
    @Environment(\.openURL) private var openURL

    @State private var terminalsSectionExpanded: Bool = true

    /// Selection binding — branch rows, worktree rows, and free-terminal rows are
    /// selectable. Folder headers have no `.tag()` and are never highlighted.
    private var listSelection: Binding<String?> {
        Binding(
            get: {
                if let activeID = projectStore.activeProjectID,
                   let active = projectStore.projects.first(where: { $0.id == activeID }) {
                    if active.isWorktree { return activeID }
                    return "branch-\(activeID)"
                }
                if let activeFree = projectStore.activeFreeTerminalID {
                    return TerminalsSection.rowTag(for: activeFree)
                }
                return nil
            },
            set: { tag in
                guard let tag else { return }
                // Defer to avoid "publishing changes from within view updates"
                // (List may call set during body evaluation when rows change)
                DispatchQueue.main.async {
                    if let termID = TerminalsSection.terminalID(fromTag: tag) {
                        projectStore.activate(.freeTerminal(termID))
                    } else if tag.hasPrefix("branch-") {
                        let projectID = String(tag.dropFirst("branch-".count))
                        projectStore.activateProject(id: projectID)
                    } else {
                        projectStore.activateProject(id: tag)
                    }
                }
            }
        )
    }

    /// Map project ID → shortcut number (1-based), derived from orderedProjectTabs
    private var shortcutMap: [String: Int] {
        var map: [String: Int] = [:]
        for (index, item) in projectStore.orderedProjectTabs.enumerated() where index < 9 {
            map[item.id] = index + 1
        }
        return map
    }

    var body: some View {
        let shortcuts = shortcutMap

        List(selection: listSelection) {
            TerminalsSection(isExpanded: $terminalsSectionExpanded)

            ForEach(projectStore.rootProjects) { project in
                // 1) Project header — no .tag(), never selectable
                ProjectHeaderRow(project: project)

                // 2) Expanded children: branch row (always) + worktree rows
                if projectStore.isExpanded(project.id) {
                    BranchRow(
                        branch: project.lastBranch ?? "No commits yet",
                        path: project.path,
                        projectID: project.id,
                        shortcutNumber: shortcuts[project.id]
                    )
                    .tag("branch-\(project.id)")

                    ForEach(projectStore.worktrees(for: project.id)) { wt in
                        WorktreeRow(wt: wt, projectID: wt.id, shortcutNumber: shortcuts[wt.id])
                            .tag(wt.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollEdgeEffectIfAvailable(for: .top)
        .navigationTitle("Projects")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if claudeStatusStore.shouldShowIncidentBanner {
                ClaudeIncidentSidebarCard(
                    title: claudeStatusStore.bannerTitle,
                    onOpenStatus: { openURL(claudeStatusStore.bannerIncidentURL) },
                    onDismiss: { claudeStatusStore.dismissCurrentIncident() }
                )
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.15), value: claudeStatusStore.shouldShowIncidentBanner)
        .overlay {
            if projectStore.projects.isEmpty {
                ContentUnavailableView {
                    Label("No Projects", systemImage: "folder.badge.plus")
                } description: {
                    Text("Open a folder to get started")
                } actions: {
                    Button("Open Folder") {
                        projectStore.openProjectPicker()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    projectStore.openProjectPicker()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Open project folder")
                .accessibilityLabel("Open project folder")
            }
        }
    }
}

private struct ClaudeIncidentSidebarCard: View {
    let title: String
    let onOpenStatus: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Color.yellow)
                Text(title)
                    .font(AppFonts.title)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(Color.yellow)

                Spacer(minLength: 4)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(AppFonts.sectionHeader)
                        .foregroundStyle(Color.yellow.opacity(0.9))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }

            Text("Anthropic is reporting an active incident.")
                .font(AppFonts.body)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Button(action: onOpenStatus) {
                HStack(spacing: 4) {
                    Text("Open status page")
                    Image(systemName: "arrow.up.right")
                        .font(AppFonts.sectionHeader)
                }
                .font(AppFonts.body.weight(.semibold))
                .foregroundStyle(Color.yellow)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.yellow.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.yellow.opacity(0.45), lineWidth: 1)
        )
    }
}

// MARK: - Project Header Row (flat, no nested children)

private struct ProjectHeaderRow: View {
    let project: ProjectItem
    @Environment(ProjectStore.self) private var projectStore
    @State private var creating = false
    @State private var hovering = false
    private var expanded: Bool { projectStore.isExpanded(project.id) }

    var body: some View {
        HStack(spacing: 4) {
            // Clickable label area — toggles expand/collapse
            HStack(spacing: 4) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(AppFonts.badge.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 12, height: 12)

                Image(systemName: "folder.fill")
                    .font(AppFonts.body)
                    .foregroundStyle(.blue)

                Text(project.displayName)
                    .font(AppFonts.body)
                    .lineLimit(1)

                // Show branch inline when collapsed
                if !expanded, let branch = project.lastBranch {
                    Text(branch)
                        .font(AppFonts.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    projectStore.toggleExpanded(project.id)
                }
            }

            Spacer(minLength: 0)

            // Create worktree button (on hover)
            if hovering || creating {
                Button {
                    Task { await createWorktree() }
                } label: {
                    if creating {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "plus.diamond")
                            .font(AppFonts.toolbarIcon)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("Create worktree")
                .accessibilityLabel("Create worktree")
                .disabled(creating)
            }
        }
        .onHover { hovering = $0 }
        .contextMenu {
            Button(expanded ? "Collapse" : "Expand") {
                withAnimation(.easeInOut(duration: 0.15)) {
                    projectStore.toggleExpanded(project.id)
                }
            }
            Divider()
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([project.url])
            }
            Button("Remove Project", role: .destructive) {
                projectStore.removeProject(id: project.id)
            }
        }
    }

    private func createWorktree() async {
        creating = true
        defer { creating = false }

        let generated = BranchNameGenerator.generate(prefix: projectStore.branchPrefix)
        let git = GitService(workingDirectory: project.url)

        do {
            let worktreePath = try await git.addWorktree(branch: generated.branchName, dirName: generated.dirName)
            let newProject = projectStore.addWorktreeProject(
                parentID: project.id,
                path: worktreePath,
                branch: generated.branchName
            )
            projectStore.activateProject(id: newProject.id)
        } catch {
            print("Failed to create worktree: \(error)")
        }
    }
}

// MARK: - Branch Row (main branch, same interaction as worktree rows)

private struct BranchRow: View {
    let branch: String
    let path: String
    let projectID: String
    var shortcutNumber: Int?

    @Environment(TerminalWorkspaceStore.self) private var workspace
    @State private var hovering = false

    private var paneInfos: [PaneInfo] { workspace.paneInfos(for: projectID) }
    private var unreadCount: Int { workspace.bellCount(for: projectID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.branch")
                    .font(AppFonts.body)
                Text(branch)
                    .font(AppFonts.body)

                Spacer(minLength: 4)

                if unreadCount > 0 {
                    Text("\(unreadCount)")
                        .font(AppFonts.badge)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .background(Capsule().fill(Color.accentColor))
                }

                if let n = shortcutNumber {
                    Text("\u{2318}\(n)")
                        .font(AppFonts.badge)
                        .foregroundStyle(.tertiary)
                }

                if hovering {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(path, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(AppFonts.smallIcon)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .help("Copy path")
                    .accessibilityLabel("Copy path")
                }
            }
            .padding(.leading, 16)

            if !paneInfos.isEmpty {
                ForEach(paneInfos) { info in
                    PaneStatusRow(info: info)
                }
            }
        }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
            }
        }
    }
}

// MARK: - Worktree Row (indented child item)

private struct WorktreeRow: View {
    let wt: ProjectItem
    let projectID: String
    var shortcutNumber: Int?
    @Environment(ProjectStore.self) private var projectStore
    @Environment(TerminalWorkspaceStore.self) private var workspace

    @State private var hovering = false
    @State private var isRenaming = false
    @State private var isArchiving = false
    @State private var renameText = ""
    @FocusState private var renameFieldFocused: Bool

    private var paneInfos: [PaneInfo] { workspace.paneInfos(for: projectID) }
    private var unreadCount: Int { workspace.bellCount(for: projectID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.branch")
                    .font(isRenaming ? AppFonts.caption : AppFonts.body)
                    .foregroundStyle(isRenaming ? .secondary : .primary)

                if isRenaming {
                    TextField("", text: $renameText)
                        .textFieldStyle(.plain)
                        .font(AppFonts.body)
                        .focused($renameFieldFocused)
                        .onSubmit {
                            let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                projectStore.renameWorktreeProject(id: wt.id, newBranch: trimmed)
                            }
                            isRenaming = false
                        }
                        .onExitCommand { isRenaming = false }
                } else {
                    Text(wt.worktreeBranch ?? wt.name)
                        .font(AppFonts.body)
                }

                Spacer(minLength: 4)

                if unreadCount > 0 {
                    Text("\(unreadCount)")
                        .font(AppFonts.badge)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .background(Capsule().fill(Color.accentColor))
                }

                if let n = shortcutNumber {
                    Text("\u{2318}\(n)")
                        .font(AppFonts.badge)
                        .foregroundStyle(.tertiary)
                }

                if hovering && !isRenaming {
                    Button {
                        startArchiveWorktree()
                    } label: {
                        if isArchiving {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "archivebox")
                                .font(AppFonts.smallIcon)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
                    .disabled(isArchiving)
                    .help(isArchiving ? "Archiving worktree..." : "Archive worktree")
                    .accessibilityLabel(isArchiving ? "Archiving worktree" : "Archive worktree")

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(wt.path, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(AppFonts.smallIcon)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .help("Copy path")
                    .accessibilityLabel("Copy path")
                }
            }
            .padding(.leading, 16)

            if !paneInfos.isEmpty {
                ForEach(paneInfos) { info in
                    PaneStatusRow(info: info)
                }
            }
        }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Rename Branch") {
                renameText = wt.worktreeBranch ?? wt.name
                isRenaming = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    renameFieldFocused = true
                }
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(wt.path, forType: .string)
            }
            Divider()
            Button(isArchiving ? "Archiving..." : "Archive Worktree", role: .destructive) {
                startArchiveWorktree()
            }
            .disabled(isArchiving)
        }
    }

    private func startArchiveWorktree() {
        guard !isArchiving else { return }
        isArchiving = true

        Task {
            let didArchive = await archiveWorktree()
            if !didArchive {
                await MainActor.run {
                    isArchiving = false
                }
            }
        }
    }

    private func archiveWorktree() async -> Bool {
        do {
            let dirty = try await GitService.hasUncommittedChanges(at: wt.url)
            if dirty {
                let proceed = await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Archive worktree?"
                    alert.informativeText = "\"\(wt.worktreeBranch ?? wt.name)\" has uncommitted changes.\n\nArchive this worktree anyway?"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Archive")
                    alert.addButton(withTitle: "Cancel")
                    return alert.runModal() == .alertFirstButtonReturn
                }
                guard proceed else { return false }
            }
        } catch {
            NSLog("openOwl: [SidebarView] Failed to check uncommitted changes: %@", error.localizedDescription)
        }

        guard let parentID = wt.worktreeOf,
              let parent = projectStore.projects.first(where: { $0.id == parentID }) else {
            await MainActor.run {
                let alert = NSAlert()
                alert.messageText = "Archive failed"
                alert.informativeText = "Could not archive \"\(wt.worktreeBranch ?? wt.name)\" because its parent project is missing."
                alert.alertStyle = .critical
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            return false
        }

        let parentGit = GitService(workingDirectory: parent.url)
        do {
            try await parentGit.removeWorktree(path: wt.path)
        } catch {
            await MainActor.run {
                let alert = NSAlert()
                alert.messageText = "Archive failed"
                alert.informativeText = "Could not archive \"\(wt.worktreeBranch ?? wt.name)\".\n\n\(error.localizedDescription)"
                alert.alertStyle = .critical
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            return false
        }

        if projectStore.activeProjectID == wt.id {
            projectStore.activateProject(id: parentID)
        }

        projectStore.removeWorktreeProject(id: wt.id)
        return true
    }
}

// MARK: - Pane Status Row (terminal pane indicator under branch/worktree)

private struct PaneStatusRow: View {
    let info: PaneInfo

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(info.hasBell ? Color.accentColor : Color.secondary.opacity(0.4))
                .frame(width: 7, height: 7)

            Text(info.title)
                .font(AppFonts.secondaryLabel)
                .foregroundStyle(info.hasBell ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .lineLimit(1)

            Spacer(minLength: 4)

            if info.hasBell {
                Image(systemName: "bell.fill")
                    .font(AppFonts.smallIcon)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.leading, 24)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(info.hasBell ? "\(info.title), has notification" : info.title)
    }
}
