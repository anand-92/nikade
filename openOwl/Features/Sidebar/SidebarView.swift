import SwiftUI

struct SidebarView: View {
    var onToggleCollapse: (() -> Void)?

    @EnvironmentObject private var projectStore: ProjectStore

    var body: some View {
        VStack(spacing: 0) {
            // 头部 "PROJECTS" + 按钮
            HStack(spacing: 6) {
                // Collapse sidebar button
                if let onToggleCollapse {
                    Button(action: onToggleCollapse) {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Collapse sidebar")
                }

                Text("PROJECTS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    projectStore.openProjectPicker()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Open project folder")
            }
            .padding(.horizontal, 12)
            .frame(height: AppConstants.headerHeight)

            Divider()

            // 项目列表
            if projectStore.projects.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Button("Open a folder") {
                        projectStore.openProjectPicker()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 13))
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(projectStore.rootProjects) { project in
                            ProjectItemView(project: project)
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

// MARK: - Project Item (root project with worktrees)

private struct ProjectItemView: View {
    let project: ProjectItem
    @EnvironmentObject private var projectStore: ProjectStore
    @State private var creating = false

    private var isActive: Bool { projectStore.activeProjectID == project.id }
    private var expanded: Bool { projectStore.isExpanded(project.id) }
    private var worktrees: [ProjectItem] { projectStore.worktrees(for: project.id) }

    var body: some View {
        VStack(spacing: 0) {
            // Project row
            HStack(spacing: 6) {
                // Expand/collapse chevron
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        projectStore.toggleExpanded(project.id)
                    }
                } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)

                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Button {
                    projectStore.activateProject(id: project.id)
                } label: {
                    HStack(spacing: 4) {
                        Text(project.displayName)
                            .lineLimit(1)
                            .font(.system(size: 12, weight: isActive ? .semibold : .regular))

                        // Show branch inline when collapsed
                        if !expanded, let branch = project.lastBranch {
                            Text(branch)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                // Create worktree button
                Button {
                    Task { await createWorktree() }
                } label: {
                    if creating {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "plus.diamond")
                            .font(.system(size: 10))
                    }
                }
                .buttonStyle(.plain)
                .opacity(0.6)
                .help("Create worktree")
                .disabled(creating)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contextMenu {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([project.url])
                }
                Button("Remove Project", role: .destructive) {
                    projectStore.removeProject(id: project.id)
                }
            }

            // Expanded: show main branch + worktrees
            if expanded {
                if let branch = project.lastBranch {
                    BranchRow(
                        label: branch,
                        isActive: isActive,
                        copyPath: project.path,
                        onSelect: { projectStore.activateProject(id: project.id) }
                    )
                }

                ForEach(worktrees) { wt in
                    WorktreeRow(
                        wt: wt,
                        isActive: projectStore.activeProjectID == wt.id,
                        onSelect: { projectStore.activateProject(id: wt.id) },
                        onArchive: { Task { await archiveWorktree(wt) } },
                        onRename: { newBranch in projectStore.renameWorktreeProject(id: wt.id, newBranch: newBranch) }
                    )
                }
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

    private func archiveWorktree(_ wt: ProjectItem) async {
        // Check for uncommitted changes
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
                guard proceed else { return }
            }
        } catch {
            // If check fails, proceed anyway
        }

        // Switch to parent if this is the active worktree
        if projectStore.activeProjectID == wt.id, let parentID = wt.worktreeOf {
            projectStore.activateProject(id: parentID)
        }

        // Use parent's git to remove the worktree
        if let parentID = wt.worktreeOf,
           let parent = projectStore.projects.first(where: { $0.id == parentID }) {
            let parentGit = GitService(workingDirectory: parent.url)
            do {
                try await parentGit.removeWorktree(path: wt.path)
            } catch {
                print("Failed to remove worktree: \(error)")
            }
        }

        projectStore.removeWorktreeProject(id: wt.id)
    }
}

// MARK: - Branch Row (main branch under project)

private struct BranchRow: View {
    let label: String
    let isActive: Bool
    let copyPath: String
    let onSelect: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 9))
                    .foregroundStyle(isActive ? Color.primary : .secondary)

                Text(label)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(isActive ? .primary : .secondary)

                Spacer(minLength: 4)

                if isActive && !hovering {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 5, height: 5)
                }

                if hovering {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(copyPath, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9))
                    }
                    .buttonStyle(.plain)
                    .opacity(0.6)
                    .help("Copy path")
                }
            }
            .padding(.leading, 28)
            .padding(.trailing, 10)
            .padding(.vertical, 3)
            .background(isActive ? Color.accentColor.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Worktree Row

private struct WorktreeRow: View {
    let wt: ProjectItem
    let isActive: Bool
    let onSelect: () -> Void
    let onArchive: () -> Void
    let onRename: (String) -> Void

    @State private var hovering = false
    @State private var isRenaming = false
    @State private var renameText = ""

    @FocusState private var renameFieldFocused: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 9))
                .foregroundStyle(isActive ? Color.primary : .secondary)

            if isRenaming {
                TextField("", text: $renameText)
                    .font(.system(size: 11))
                    .textFieldStyle(.roundedBorder)
                    .focused($renameFieldFocused)
                    .onSubmit {
                        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { onRename(trimmed) }
                        isRenaming = false
                    }
                    .onExitCommand { isRenaming = false }
            } else {
                Text(wt.worktreeBranch ?? wt.name)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(isActive ? .primary : .secondary)
            }

            Spacer(minLength: 4)

            if isActive && !hovering && !isRenaming {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 5, height: 5)
            }

            if hovering && !isRenaming {
                Button {
                    onArchive()
                } label: {
                    Image(systemName: "archivebox")
                        .font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .opacity(0.6)
                .help("Archive worktree")

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(wt.path, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .opacity(0.6)
                .help("Copy path")
            }
        }
        .padding(.leading, 28)
        .padding(.trailing, 10)
        .padding(.vertical, 3)
        .background(isActive ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) {
            renameText = wt.worktreeBranch ?? wt.name
            isRenaming = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                renameFieldFocused = true
            }
        }
        .onTapGesture(count: 1) {
            if !isRenaming { onSelect() }
        }
    }
}
