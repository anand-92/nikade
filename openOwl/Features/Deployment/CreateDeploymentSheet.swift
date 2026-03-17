import SwiftUI

enum DeploymentKind: String, CaseIterable {
    case local = "Local"
    case remote = "Remote"
}

struct CreateDeploymentSheet: View {
    @Environment(DeploymentStore.self) private var deploymentStore
    @Environment(ProjectStore.self) private var projectStore
    @Environment(AppNavigationStore.self) private var navigationStore
    @Environment(\.dismiss) private var dismiss

    @State private var kind: DeploymentKind = .local
    @State private var name = ""
    @State private var branch = "main"
    @State private var installCommand = ""
    @State private var buildCommand = ""
    @State private var startCommand = ""
    @State private var envVars = ""
    @State private var portString = "3000"
    @State private var healthCheckURL = ""
    @State private var didSetDefaults = false

    private var activeProject: ProjectItem? {
        guard let id = projectStore.activeProjectID else { return nil }
        return projectStore.projects.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("New Deployment")
                .font(.system(size: 14, weight: .semibold))
                .padding(.top, 16)
                .padding(.bottom, 12)

            Form {
                Picker("Type", selection: $kind) {
                    ForEach(DeploymentKind.allCases, id: \.self) { k in
                        Text(k.rawValue).tag(k)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Name", text: $name, prompt: Text("e.g. production"))

                if kind == .local {
                    TextField("Branch", text: $branch, prompt: Text("main"))
                    TextField("Install Command", text: $installCommand, prompt: Text("npm install"))
                    TextField("Build Command", text: $buildCommand, prompt: Text("npm run build"))
                    TextField("Start Command", text: $startCommand, prompt: Text("npm start"))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Environment Variables")
                        TextEditor(text: $envVars)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(height: 60)
                            .overlay(alignment: .topLeading) {
                                if envVars.isEmpty {
                                    Text("KEY=VALUE (one per line)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.quaternary)
                                        .padding(.top, 8)
                                        .padding(.leading, 5)
                                        .allowsHitTesting(false)
                                }
                            }
                    }

                    TextField("Port", text: $portString, prompt: Text("3000"))
                }

                TextField("Health Check URL", text: $healthCheckURL,
                          prompt: Text(kind == .remote ? "https://example.com/health" : "http://localhost:3000/health"))
            }
            .formStyle(.grouped)
            .scrollDisabled(kind == .remote)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button(kind == .remote ? "Add" : "Deploy") { deploy() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isFormValid)
            }
            .padding(16)
        }
        .frame(width: 400)
        .onAppear {
            guard !didSetDefaults else { return }
            didSetDefaults = true
            if let project = activeProject {
                name = project.displayName
            }
        }
    }

    private var isFormValid: Bool {
        let hasName = !name.trimmingCharacters(in: .whitespaces).isEmpty
        if kind == .remote {
            return hasName && !healthCheckURL.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return hasName && !branch.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func deploy() {
        guard let project = activeProject else { return }

        let projectID = project.id
        let finalName = name.trimmingCharacters(in: .whitespaces)
        let finalHealthURL = healthCheckURL.trimmingCharacters(in: .whitespaces)

        navigationStore.activeTab = .deployments
        dismiss()

        if kind == .remote {
            deploymentStore.createRemoteMonitor(
                projectID: projectID,
                name: finalName,
                healthCheckURL: finalHealthURL
            )
            return
        }

        // Local deployment
        let projectURL = project.url
        let finalBranch = branch.trimmingCharacters(in: .whitespaces)
        let finalInstall = installCommand.trimmingCharacters(in: .whitespaces)
        let finalBuild = buildCommand.trimmingCharacters(in: .whitespaces)
        let finalStart = startCommand.trimmingCharacters(in: .whitespaces)
        let trimmedEnv = envVars.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = Int(portString.trimmingCharacters(in: .whitespaces))

        Task {
            do {
                let remoteURL: String = try await withCheckedThrowingContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        let proc = Process()
                        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                        proc.arguments = ["git", "config", "--get", "remote.origin.url"]
                        proc.currentDirectoryURL = projectURL
                        let pipe = Pipe()
                        proc.standardOutput = pipe
                        proc.standardError = Pipe()
                        do {
                            try proc.run()
                            let data = pipe.fileHandleForReading.readDataToEndOfFile()
                            proc.waitUntilExit()
                            if proc.terminationStatus == 0 {
                                continuation.resume(returning: String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
                            } else {
                                continuation.resume(throwing: DeploymentError.cloneFailed("No remote origin configured"))
                            }
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }

                try await deploymentStore.createDeployment(
                    projectID: projectID,
                    name: finalName,
                    branch: finalBranch,
                    installCommand: finalInstall.isEmpty ? "npm install" : finalInstall,
                    buildCommand: finalBuild.isEmpty ? "npm run build" : finalBuild,
                    startCommand: finalStart.isEmpty ? "npm start" : finalStart,
                    envVars: trimmedEnv.isEmpty ? nil : trimmedEnv,
                    port: port,
                    healthCheckURL: finalHealthURL.isEmpty ? nil : finalHealthURL,
                    remoteURL: remoteURL
                )
            } catch {
                NSLog("Deployment failed: %@", error.localizedDescription)
            }
        }
    }
}
