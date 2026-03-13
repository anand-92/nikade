import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var navigationStore: AppNavigationStore
    @EnvironmentObject private var projectStore: ProjectStore

    var body: some View {
        VStack(spacing: 0) {
            projectSection

            Divider()

            List(selection: $navigationStore.selection) {
                Section("Workspace") {
                    Label("Terminal", systemImage: "terminal")
                        .tag(SidebarSelection.terminal)

                    Label("Git Changes", systemImage: "point.bottomleft.forward.to.point.topright.scurvepath")
                        .tag(SidebarSelection.gitChanges)

                    Label("Files", systemImage: "folder")
                        .tag(SidebarSelection.fileExplorer)
                }
            }
            .listStyle(.sidebar)
        }
        .navigationTitle(AppConstants.appName)
    }

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Projects")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Button {
                    projectStore.openProjectPicker()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Open project folder")
            }

            if projectStore.projects.isEmpty {
                Text("No projects")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(projectStore.projects) { project in
                            projectRow(project)
                        }
                    }
                }
                .frame(maxHeight: 140)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func projectRow(_ project: ProjectItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.system(size: 11))
                .foregroundStyle(projectStore.activeProjectID == project.id ? Color.accentColor : .secondary)

            Button {
                projectStore.activateProject(id: project.id)
            } label: {
                Text(project.displayName)
                    .lineLimit(1)
                    .font(.system(size: 12, weight: projectStore.activeProjectID == project.id ? .semibold : .regular))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(projectStore.activeProjectID == project.id ? Color.accentColor.opacity(0.15) : Color.clear)
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
