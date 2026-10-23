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

    @Test("any bound port matches, ephemeral ones included")
    func secondaryPortMatches() {
        let service = makeService(port: 3000, project: nil, pid: 30,
                                  hosts: [("127.0.0.1", 3000), ("127.0.0.1", 9229), ("127.0.0.1", 55000)])
        let result = ScanResult(services: [service], groups: [], standalone: [service], allSockets: [], hidden: [])
        #expect(result.matching("9229").services.map(\.port) == [3000])
        #expect(result.matching("55000").services.map(\.port) == [3000])
        #expect(result.matching("54000-56000").services.map(\.port) == [3000])
    }

    @Test("a number matches a pid exactly, never a pid that merely contains it")
    func pidMatchesExactly() {
        #expect(scan.matching("20").services.map(\.port) == [5432])
        #expect(scan.matching("0").services.isEmpty)
    }

    @Test("a range matches any port inside it, ends included")
    func portRangeMatches() {
        #expect(scan.matching("5000-5173").services.map(\.port) == [5173])
        #expect(scan.matching("5000 - 6000").services.map(\.port) == [5173, 5432])
        #expect(scan.matching("6000-5000").services.isEmpty)
    }

    @Test("text reaches the command line, a number does not")
    func commandLineMatchesText() {
        let vite = makeService(port: 5173, project: nil, pid: 10, executable: "/opt/homebrew/bin/node",
                               arguments: ["node", "node_modules/.bin/vite", "--port", "5173", "--host"])
        let result = ScanResult(services: [vite], groups: [], standalone: [vite], allSockets: [], hidden: [])
        #expect(result.matching("--host").services.count == 1)
        #expect(result.matching("node_modules/.bin/vite").services.count == 1)
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
