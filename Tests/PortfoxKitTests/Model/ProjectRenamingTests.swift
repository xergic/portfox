import Foundation
import Testing
@testable import PortfoxKit

@Suite("Renaming projects")
struct ProjectRenamingTests {
    private func snapshot(_ root: String, name: String) -> ProjectSnapshot {
        makeSnapshot(root: URL(fileURLWithPath: root), name: name)
    }

    private func result(_ services: [RunningService]) -> ScanResult {
        let groups = services.compactMap { service in
            service.project.map { ProjectGroup(project: Project(root: $0.root, name: $0.name), services: [service]) }
        }
        return ScanResult(services: services, groups: groups, standalone: [], allSockets: [], hidden: [])
    }

    @Test("no custom name returns the same result")
    func noRenameIsIdentity() {
        let scan = result([makeService(port: 3000, project: snapshot("/repo/api", name: "wishfox-api"))])
        #expect(scan.renamingProjects { _ in nil } == scan)
    }

    @Test("a renamed root renames its heading and every service in it")
    func renameReachesHeadingAndServices() {
        let scan = result([makeService(port: 3000, project: snapshot("/repo/api", name: "wishfox-api"))])
        let renamed = scan.renamingProjects { $0.path == "/repo/api" ? "Wishfox API" : nil }

        #expect(renamed.groups.map(\.project.name) == ["Wishfox API"])
        #expect(renamed.services.map(\.project?.name) == ["Wishfox API"])
        #expect(renamed.groups[0].services.map(\.project?.name) == ["Wishfox API"])
    }

    @Test("headings are re-sorted by the new name")
    func headingsResort() {
        let scan = result([
            makeService(port: 3000, project: snapshot("/repo/a", name: "alpha"), pid: 1),
            makeService(port: 4000, project: snapshot("/repo/b", name: "beta"), pid: 2)
        ])
        let renamed = scan.renamingProjects { $0.path == "/repo/a" ? "zeta" : nil }
        #expect(renamed.groups.map(\.project.name) == ["beta", "zeta"])
    }
}
