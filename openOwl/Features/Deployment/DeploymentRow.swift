import SwiftUI

struct DeploymentRow: View {
    let deployment: Deployment
    @Environment(DeploymentStore.self) private var deploymentStore
    @Environment(AppNavigationStore.self) private var navigationStore
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 5) {
            // Status icon — matches Label icon position of BranchRow
            Image(systemName: statusIcon)
                .font(.system(size: 7))
                .foregroundStyle(statusColor)
                .frame(width: 14, alignment: .center)

            Text(deployment.name)
                .font(.system(size: 12))
                .lineLimit(1)

            Spacer(minLength: 4)

            if hovering && !deployment.isRemote {
                Button {
                    toggleDeployment()
                } label: {
                    Image(systemName: deployment.status == .running ? "stop.fill" : "play.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(deployment.status == .running ? "Stop" : "Start")
            }
        }
        .padding(.leading, 16)
        .onHover { hovering = $0 }
        .onTapGesture {
            deploymentStore.selectedDeploymentID = deployment.id
            navigationStore.activeTab = .deployments
        }
        .contextMenu {
            if !deployment.isRemote {
                if deployment.status == .running {
                    Button("Stop") {
                        Task { await deploymentStore.stop(id: deployment.id) }
                    }
                    Button("Restart") {
                        Task { try? await deploymentStore.restart(id: deployment.id) }
                    }
                } else {
                    Button("Start") {
                        Task { try? await deploymentStore.start(id: deployment.id) }
                    }
                }
                Divider()
            }

            Button("Delete", role: .destructive) {
                Task { await deploymentStore.removeDeployment(id: deployment.id) }
            }
        }
    }

    private var statusIcon: String {
        if deployment.isRemote {
            // Remote: show health status
            return "globe"
        }
        switch deployment.status {
        case .running: return "circle.fill"
        case .error: return "exclamationmark.circle.fill"
        case .building: return "circle.dotted.circle"
        case .stopped: return "circle"
        }
    }

    private var statusColor: Color {
        if deployment.isRemote {
            if let healthy = deploymentStore.healthStatus[deployment.id] {
                return healthy ? AppColors.success : AppColors.error
            }
            return .secondary
        }
        return deployment.status.color
    }

    private func toggleDeployment() {
        Task {
            if deployment.status == .running {
                await deploymentStore.stop(id: deployment.id)
            } else {
                try? await deploymentStore.start(id: deployment.id)
            }
        }
    }
}
