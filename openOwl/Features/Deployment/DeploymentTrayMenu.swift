import SwiftUI

struct DeploymentTrayMenu: View {
    @Environment(DeploymentStore.self) private var deploymentStore
    @Environment(AppNavigationStore.self) private var navigationStore
    @Environment(ProjectStore.self) private var projectStore

    var body: some View {
        if deploymentStore.deployments.isEmpty {
            Text("No Deployments")
                .foregroundStyle(.secondary)
        } else {
            ForEach(deploymentStore.deployments) { dep in
                if dep.isRemote {
                    remoteMenuItem(dep)
                } else {
                    localMenuItem(dep)
                }
            }
        }

        Divider()

        Button("Open openOwl") {
            Self.activateMainWindow()
        }

        Button("Quit openOwl") {
            for dep in deploymentStore.deployments where !dep.isRemote && dep.status == .running {
                Task { await deploymentStore.stop(id: dep.id) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: - Local: Start/Stop/Restart

    private func localMenuItem(_ dep: Deployment) -> some View {
        Menu {
            if dep.status == .running {
                Button("Stop") {
                    Task { await deploymentStore.stop(id: dep.id) }
                }
                Button("Restart") {
                    Task { try? await deploymentStore.restart(id: dep.id) }
                }
            } else if dep.status != .building {
                Button("Start") {
                    Task { try? await deploymentStore.start(id: dep.id) }
                }
            }
            Divider()
            Button("Open Config") {
                openDeployment(dep.id)
            }
        } label: {
            Text("\(dep.name)  \(dep.status.displayLabel)")
        }
    }

    // MARK: - Remote: read-only health status

    private func remoteMenuItem(_ dep: Deployment) -> some View {
        let label: String
        switch deploymentStore.healthStatus[dep.id] {
        case true: label = "Healthy"
        case false: label = "Down"
        case nil: label = "Checking"
        }

        return Button("\(dep.name)  \(label)") {
            openDeployment(dep.id)
        }
    }

    private func openDeployment(_ id: String) {
        Self.activateMainWindow()
        // Notify main window via NotificationCenter -- MenuBarExtra .menu style
        // doesn't reliably share SwiftUI environment writes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(
                name: .openDeployment,
                object: nil,
                userInfo: ["id": id]
            )
        }
    }

    // MARK: - Helpers

    private static func activateMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
            break
        }
    }
}

extension Notification.Name {
    static let openDeployment = Notification.Name("openowl.openDeployment")
    static let quickOpen = Notification.Name("openowl.quickOpen")
    static let terminalSearch = Notification.Name("openowl.terminalSearch")
}
