import SwiftUI

struct DeploymentPanelView: View {
    @EnvironmentObject private var deploymentStore: DeploymentStore
    @EnvironmentObject private var projectStore: ProjectStore
    @State private var showCreateSheet = false

    private var projectDeployments: [Deployment] {
        guard let activeID = projectStore.activeProjectID else { return [] }
        return deploymentStore.deployments(for: activeID)
    }

    var body: some View {
        HSplitView {
            deploymentList
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 300)

            deploymentDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Left: Deployment List

    private var deploymentList: some View {
        VStack(spacing: 0) {
            List(selection: $deploymentStore.selectedDeploymentID) {
                ForEach(projectDeployments) { dep in
                    DeploymentListItem(deployment: dep)
                        .tag(dep.id)
                }
            }
            .listStyle(.sidebar)

            Divider()

            Button {
                showCreateSheet = true
            } label: {
                Label("New Deployment", systemImage: "plus")
                    .font(AppFonts.primaryLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateDeploymentSheet()
        }
    }

    // MARK: - Right: Detail

    @ViewBuilder
    private var deploymentDetail: some View {
        if let selectedID = deploymentStore.selectedDeploymentID,
           let dep = projectDeployments.first(where: { $0.id == selectedID }) {
            DeploymentDetailView(deployment: dep)
        } else if let first = projectDeployments.first {
            DeploymentDetailView(deployment: first)
                .onAppear { deploymentStore.selectedDeploymentID = first.id }
        } else {
            ContentUnavailableView {
                Label("No Deployment Selected", systemImage: "shippingbox")
            } description: {
                Text("Select a deployment from the list or create a new one")
            }
        }
    }
}

// MARK: - List Item

private struct DeploymentListItem: View {
    let deployment: Deployment
    @EnvironmentObject private var deploymentStore: DeploymentStore

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(deployment.name)
                    .font(AppFonts.primaryLabel)
                    .lineLimit(1)

                Text(subtitle)
                    .font(AppFonts.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if !deployment.isRemote && deployment.status == .building {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        if deployment.isRemote {
            // Show host from URL, e.g. "192.168.50.98:9000"
            if let urlString = deployment.healthCheckURL,
               let url = URL(string: urlString),
               let host = url.host {
                let port = url.port.map { ":\($0)" } ?? ""
                return host + port
            }
            return "Remote"
        }
        return deployment.branch
    }

    private var statusColor: Color {
        if deployment.isRemote {
            if let healthy = deploymentStore.healthStatus[deployment.id] {
                return healthy ? AppColors.success : AppColors.error
            }
            return .gray
        }
        switch deployment.status {
        case .running: return AppColors.success
        case .error: return AppColors.error
        case .building: return AppColors.warning
        case .stopped: return .gray
        }
    }
}

// MARK: - Detail View

private struct DeploymentDetailView: View {
    let deployment: Deployment
    @EnvironmentObject private var deploymentStore: DeploymentStore
    @State private var isPerformingAction = false

    // Editable fields
    @State private var editName = ""
    @State private var editBranch = ""
    @State private var editInstallCommand = ""
    @State private var editBuildCommand = ""
    @State private var editStartCommand = ""
    @State private var editEnvVars = ""
    @State private var editPortString = ""
    @State private var editHealthCheckURL = ""

    private var hasUnsavedChanges: Bool {
        editName != deployment.name
            || editBranch != deployment.branch
            || editInstallCommand != (deployment.installCommand ?? "")
            || editBuildCommand != (deployment.buildCommand ?? "")
            || editStartCommand != (deployment.startCommand ?? "")
            || editEnvVars != (deployment.envVars ?? "")
            || editPortString != (deployment.port.map { "\($0)" } ?? "")
            || editHealthCheckURL != (deployment.healthCheckURL ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header + config
            ScrollView {
                detailHeader
                    .padding(16)
            }
            .frame(maxHeight: deployment.isRemote ? .infinity : 320)

            if !deployment.isRemote {
                Divider()
                logSection
            }
        }
        .onAppear { syncFields() }
        .onChange(of: deployment.id) { _, _ in
            syncFields()
            if !deployment.isRemote {
                deploymentStore.loadLog(for: deployment.id)
            }
        }
    }

    private func syncFields() {
        editName = deployment.name
        editBranch = deployment.branch
        editInstallCommand = deployment.installCommand ?? ""
        editBuildCommand = deployment.buildCommand ?? ""
        editStartCommand = deployment.startCommand ?? ""
        editEnvVars = deployment.envVars ?? ""
        editPortString = deployment.port.map { "\($0)" } ?? ""
        editHealthCheckURL = deployment.healthCheckURL ?? ""
        deploymentStore.loadLog(for: deployment.id)
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title + status
            HStack {
                Text(deployment.name)
                    .font(.system(size: 16, weight: .semibold))

                if deployment.isRemote {
                    Text("Remote")
                        .font(AppFonts.badge)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .foregroundStyle(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    StatusBadge(status: deployment.status)
                }

                // Health check indicator
                if let healthy = deploymentStore.healthStatus[deployment.id] {
                    HealthBadge(
                        healthy: healthy,
                        error: deploymentStore.healthError[deployment.id],
                        lastChecked: deploymentStore.healthLastChecked[deployment.id]
                    )
                } else if deployment.healthCheckURL != nil {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text("Checking...")
                            .font(AppFonts.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let commit = deployment.lastCommit {
                    Text(String(commit.prefix(7)))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            // Action buttons (local deployments only)
            if !deployment.isRemote {
                HStack(spacing: 8) {
                    if deployment.status == .running {
                        ActionButton(title: "Stop", color: AppColors.success, isLoading: isPerformingAction) {
                            performAction { await deploymentStore.stop(id: deployment.id) }
                        }
                    } else if deployment.status == .building {
                        ActionButton(title: "Building", color: AppColors.warning, isLoading: true) {}
                    } else {
                        ActionButton(title: "Start", color: AppColors.error, isLoading: isPerformingAction) {
                            performAction { try await deploymentStore.start(id: deployment.id) }
                        }
                    }

                    if deployment.status == .running {
                        ActionButton(title: "Restart", color: .blue, isLoading: false) {
                            performAction { try await deploymentStore.restart(id: deployment.id) }
                        }
                    }

                    Spacer()

                    Button(role: .destructive) {
                        performAction { await deploymentStore.removeDeployment(id: deployment.id) }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Delete deployment")
                }
            } else {
                // Remote: only delete
                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        performAction { await deploymentStore.removeDeployment(id: deployment.id) }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Delete deployment")
                }
            }

            Divider()

            // Editable config
            configSection
        }
    }

    private var configSection: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                Text("Name").foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                TextField("", text: $editName, prompt: Text("deployment name"))
                    .textFieldStyle(.roundedBorder)
            }

            if !deployment.isRemote {
                GridRow {
                    Text("Branch").foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                    TextField("", text: $editBranch, prompt: Text("main"))
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Install").foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                    TextField("", text: $editInstallCommand, prompt: Text("npm install"))
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Build").foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                    TextField("", text: $editBuildCommand, prompt: Text("npm run build"))
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Start").foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                    TextField("", text: $editStartCommand, prompt: Text("npm start"))
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Port").foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                    TextField("", text: $editPortString, prompt: Text("3000"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
            }

            GridRow {
                Text("Health").foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                TextField("", text: $editHealthCheckURL, prompt: Text(deployment.isRemote ? "https://example.com/health" : "http://localhost:3000/health"))
                    .textFieldStyle(.roundedBorder)
            }

            if !deployment.isRemote {
                GridRow(alignment: .top) {
                    Text("Env").foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                    TextEditor(text: $editEnvVars)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(height: 50)
                        .border(Color.secondary.opacity(0.2))
                        .overlay(alignment: .topLeading) {
                            if editEnvVars.isEmpty {
                                Text("KEY=VALUE")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.quaternary)
                                    .padding(.top, 4)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }

            GridRow {
                Spacer().frame(width: 80)
                HStack {
                    Button("Save") {
                        deploymentStore.updateDeployment(
                            id: deployment.id,
                            name: editName,
                            branch: editBranch,
                            installCommand: editInstallCommand,
                            buildCommand: editBuildCommand,
                            startCommand: editStartCommand,
                            envVars: editEnvVars,
                            port: Int(editPortString.trimmingCharacters(in: .whitespaces)),
                            healthCheckURL: editHealthCheckURL
                        )
                    }
                    .disabled(!hasUnsavedChanges)

                    if hasUnsavedChanges {
                        Text("Unsaved changes")
                            .font(AppFonts.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .font(AppFonts.secondaryLabel)
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Logs")
                    .font(AppFonts.sectionHeader)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)

                Spacer()

                Button {
                    deploymentStore.loadLog(for: deployment.id)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.trailing, 16)
                .help("Refresh logs")
            }

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    Text(deploymentStore.logContent.isEmpty ? "No logs yet." : deploymentStore.logContent)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(deploymentStore.logContent.isEmpty ? Color.gray : Color(nsColor: .init(white: 0.85, alpha: 1)))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .textSelection(.enabled)
                        .id("logBottom")
                }
                .background(Color(nsColor: .init(white: 0.1, alpha: 1)))
                .onChange(of: deploymentStore.logContent) { _, _ in
                    withAnimation {
                        proxy.scrollTo("logBottom", anchor: .bottom)
                    }
                }
            }
        }
    }

    private func performAction(_ action: @escaping () async throws -> Void) {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        Task {
            defer { isPerformingAction = false }
            try? await action()
        }
    }
}

// MARK: - Status Badge

private struct StatusBadge: View {
    let status: DeploymentStatus

    var body: some View {
        Text(status.rawValue.capitalized)
            .font(AppFonts.badge)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var color: Color {
        switch status {
        case .running: return AppColors.success
        case .error: return AppColors.error
        case .building: return AppColors.warning
        case .stopped: return .gray
        }
    }
}

// MARK: - Action Button

private struct ActionButton: View {
    let title: String
    let color: Color
    let isLoading: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                }
                Text(title)
                    .font(AppFonts.primaryLabel)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: AppSpacing.cornerRadius)
                    .fill(hovering ? AppColors.hoverBackground : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppSpacing.cornerRadius)
                    .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .onHover { hovering = $0 }
    }
}

// MARK: - Health Badge

private struct HealthBadge: View {
    let healthy: Bool
    let error: String?
    let lastChecked: Date?

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(healthy ? AppColors.success : AppColors.error)
                .frame(width: 6, height: 6)

            Text(healthy ? "Healthy" : "Down")
                .font(AppFonts.badge)

            if !healthy, let error {
                Text("· \(error)")
                    .font(AppFonts.badge)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let lastChecked {
                Text("· \(Self.timeFormatter.string(from: lastChecked))")
                    .font(AppFonts.badge)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background((healthy ? AppColors.success : AppColors.error).opacity(0.12))
        .foregroundStyle(healthy ? AppColors.success : AppColors.error)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
