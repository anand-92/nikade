import Testing
import Foundation
@testable import openOwl

@Suite("Deployment Codable")
struct DeploymentCodableTests {

    @Test func roundTrip() throws {
        let original = Deployment(
            id: "d1",
            projectID: "p1",
            name: "My Service",
            isRemote: true,
            branch: "main",
            installCommand: "npm install",
            buildCommand: "npm run build",
            startCommand: "npm start",
            envVars: "PORT=3000",
            port: 3000,
            healthCheckURL: "http://localhost:3000/health",
            status: .running,
            pid: 1234,
            clonePath: "/tmp/clone",
            remoteURL: "https://github.com/user/repo",
            lastCommit: "abc123"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Deployment.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.isRemote == true)
        #expect(decoded.branch == "main")
        #expect(decoded.port == 3000)
        #expect(decoded.status == .running)
        #expect(decoded.pid == 1234)
        #expect(decoded.clonePath == "/tmp/clone")
        #expect(decoded.remoteURL == "https://github.com/user/repo")
        #expect(decoded.lastCommit == "abc123")
    }

    @Test func minimalJSON_defaultValues() throws {
        let json = """
        {
            "id": "d2",
            "projectID": "p1",
            "name": "Minimal",
            "status": "stopped"
        }
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(Deployment.self, from: data)

        #expect(decoded.id == "d2")
        #expect(decoded.isRemote == false)
        #expect(decoded.branch == "")
        #expect(decoded.installCommand == nil)
        #expect(decoded.port == nil)
        #expect(decoded.clonePath == "")
        #expect(decoded.remoteURL == "")
        #expect(decoded.lastCommit == nil)
    }

    // MARK: - parseEnvString

    @Test func parseEnvString_keyValue() {
        let result = DeploymentProcessManager.parseEnvString("PORT=3000\nHOST=localhost")
        #expect(result == ["PORT": "3000", "HOST": "localhost"])
    }

    @Test func parseEnvString_quotedValues() {
        let result = DeploymentProcessManager.parseEnvString("""
        SECRET="my secret"
        SINGLE='value'
        """)
        #expect(result["SECRET"] == "my secret")
        #expect(result["SINGLE"] == "value")
    }

    @Test func parseEnvString_commentsAndEmptyLines() {
        let result = DeploymentProcessManager.parseEnvString("""
        # This is a comment
        KEY=value

        # Another comment
        OTHER=data
        """)
        #expect(result == ["KEY": "value", "OTHER": "data"])
    }

    @Test func parseEnvString_empty() {
        let result = DeploymentProcessManager.parseEnvString("")
        #expect(result.isEmpty)
    }
}
