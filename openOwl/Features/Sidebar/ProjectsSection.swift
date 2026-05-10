import SwiftUI

/// "PROJECTS" sidebar section header — collapsible group above the
/// project list. The body (ForEach over rootProjects with branch/worktree
/// rows) lives in SidebarView because it threads the shortcutMap and
/// selection routing — only the header row is encapsulated here so it
/// mirrors `TerminalsSection`'s structure.
///
/// Inactive sub-section: projects that have been added but don't yet own
/// a terminal tab in the current session live under a collapsed
/// `InactiveProjectsHeaderRow` to keep the sidebar focused on what the
/// user is currently working on. Clicking an `InactiveProjectRow`
/// activates the project (creating its first tab) and the row reflows up
/// into the active group on the next render.
struct ProjectsHeaderRow: View {
    @Environment(ProjectStore.self) private var projectStore
    @Binding var isExpanded: Bool

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(AppFonts.badge.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 12, height: 12)

                Text("PROJECTS")
                    .font(AppFonts.sectionHeader)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            }

            Spacer(minLength: 0)

            Button {
                projectStore.openProjectPicker()
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(AppFonts.toolbarIcon)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open project folder")
            .accessibilityLabel("Open project folder")
        }
    }
}

// MARK: - Inactive Sub-section

struct InactiveProjectsHeaderRow: View {
    let count: Int
    @Binding var isExpanded: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(AppFonts.badge.weight(.semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 12, height: 12)

            Text("INACTIVE")
                .font(AppFonts.sectionHeader)
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Text("\(count)")
                .font(AppFonts.badge)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 3))

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded.toggle()
            }
        }
    }
}

struct InactiveProjectRow: View {
    let project: ProjectItem
    @Environment(ProjectStore.self) private var projectStore
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "folder")
                .font(AppFonts.body)
                .foregroundStyle(.tertiary)

            Text(project.displayName)
                .font(AppFonts.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.leading, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            projectStore.activateProject(id: project.id)
        }
        .onHover { hovering = $0 }
        .background(
            hovering
                ? AppColors.hoverBackground.cornerRadius(AppSpacing.cornerRadiusSmall)
                : Color.clear.cornerRadius(AppSpacing.cornerRadiusSmall)
        )
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([project.url])
            }
            Button("Remove Project", role: .destructive) {
                projectStore.removeProject(id: project.id)
            }
        }
    }
}
