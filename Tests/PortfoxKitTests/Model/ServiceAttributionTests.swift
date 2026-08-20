import Foundation
import Testing
@testable import PortfoxKit

@Suite("what identifies a service")
struct ServiceAttributionTests {
    private func detection(_ type: ServiceType) -> DetectionResult {
        DetectionResult(type: type, score: 10, confidence: 1, evidence: [])
    }

    private func snapshot(_ path: String, rootKind: ProjectSnapshot.RootKind) -> ProjectSnapshot {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        return makeSnapshot(root: url, name: url.lastPathComponent, rootKind: rootKind)
    }

    /// The bug this guards: the detail pane headlined DBngin's Postgres with
    /// "Project: 3C934D2E-C1E9-436E-A961-43D76B94F4DD", its data directory.
    @Test("a database never claims the project resolved from its data directory")
    func databaseRejectsItsDataDirectory() {
        let service = makeService(
            port: 5435,
            project: snapshot(
                "/Users/me/Library/Application Support/com.tinyapp.DBngin/Engines/postgresql/3C934D2E",
                rootKind: .git
            ),
            executable: "/Users/Shared/DBngin/postgresql/17.0/bin/postgres",
            detection: detection(.postgres)
        )
        #expect(service.projectIdentifiesService == false)
        #expect(service.installationSource == "DBngin")
    }

    @Test("a daemon installed by Homebrew is labelled Homebrew")
    func homebrewDaemon() {
        let service = makeService(
            port: 5432,
            project: nil,
            executable: "/opt/homebrew/opt/postgresql@17/bin/postgres",
            detection: detection(.postgres)
        )
        #expect(service.installationSource == "Homebrew")
    }

    @Test("an installer Portfox does not recognise yields no source")
    func unknownInstaller() {
        let service = makeService(
            port: 5432,
            project: nil,
            executable: "/usr/bin/postgres",
            detection: detection(.postgres)
        )
        #expect(service.installationSource == nil)
    }

    @Test("a dev server in a git repository is identified by its project")
    func developmentServerKeepsItsProject() {
        let service = makeService(
            port: 5173,
            project: snapshot("/Users/me/work/shop", rootKind: .git),
            executable: "/opt/homebrew/bin/node",
            detection: detection(.vite)
        )
        #expect(service.projectIdentifiesService)
    }

    /// A bare directory is where the process happens to have been started, which
    /// says nothing about what the service is.
    @Test("a project resolved from the working directory alone identifies nothing")
    func bareDirectoryIsNotAProject() {
        let service = makeService(
            port: 5173,
            project: snapshot("/Users/me/Downloads", rootKind: .directory),
            executable: "/opt/homebrew/bin/node",
            detection: detection(.vite)
        )
        #expect(service.projectIdentifiesService == false)
    }
}
