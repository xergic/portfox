import Foundation
import Testing
@testable import PortfoxKit

@Suite("Searching a scan result")
struct ScanResultSearchTests {
    private let scan: ScanResult = {
        let services = [
            makeService(port: 5173, project: nil, pid: 10, executable: "/opt/homebrew/bin/node"),
            makeService(port: 5432, project: nil, pid: 20, executable: "/opt/homebrew/bin/postgres")
        ]
        return ScanResult(services: services, groups: [], standalone: services, allSockets: [], hidden: [])
    }()

    @Test("a blank query keeps everything")
    func blankQueryKeepsEverything() {
        #expect(scan.matching("  ") == scan)
    }

    @Test("a port prefix finds the service on that port")
    func portMatches() {
        #expect(scan.matching("517").services.map(\.port) == [5173])
    }

    @Test("the binary name matches case-insensitively and trimmed")
    func binaryMatches() {
        #expect(scan.matching(" Postgres ").services.map(\.port) == [5432])
    }

    @Test("no match leaves every list empty")
    func noMatchEmptiesEverything() {
        let none = scan.matching("redis")
        #expect(none.services.isEmpty)
        #expect(none.standalone.isEmpty)
    }

    @Test("drawing order puts project groups before infrastructure")
    func drawingOrderLeadsWithGroups() {
        let web = makeService(port: 3000, project: nil, pid: 30)
        let database = makeService(port: 5432, project: nil, pid: 20)
        let result = ScanResult(
            services: [database, web],
            groups: [ProjectGroup(project: Project(root: URL(fileURLWithPath: "/repo"), name: "repo"), services: [web])],
            standalone: [database],
            allSockets: [],
            hidden: []
        )

        #expect(result.drawingOrder.map(\.port) == [3000, 5432])
    }
}
