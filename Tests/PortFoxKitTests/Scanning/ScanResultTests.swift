import Foundation
import Testing
@testable import PortFoxKit

@Suite("narrowing a scan result")
struct ScanResultTests {
    private func service(_ id: String, port: Int) -> RunningService {
        makeService(port: port, project: nil, pid: pid_t(port), id: id)
    }

    private func group(_ name: String, _ services: [RunningService]) -> ProjectGroup {
        ProjectGroup(
            project: Project(root: URL(fileURLWithPath: "/Users/me/\(name)", isDirectory: true), name: name),
            services: services
        )
    }

    private func result() -> ScanResult {
        let shopWeb = service("shop-web", port: 3000)
        let shopAPI = service("shop-api", port: 3001)
        let blog = service("blog", port: 4000)
        let postgres = service("postgres", port: 5432)

        return ScanResult(
            services: [shopWeb, shopAPI, blog, postgres],
            groups: [group("shop", [shopWeb, shopAPI]), group("blog", [blog])],
            standalone: [postgres],
            allSockets: [shopWeb, shopAPI, blog, postgres].map(\.primarySocket),
            hidden: [service("cups", port: 631)]
        )
    }

    @Test("a predicate that keeps everything returns an equal value")
    func keepingEverythingIsIdentity() {
        let original = result()
        #expect(original.keeping { _ in true } == original)
    }

    @Test("a group loses only the services the predicate rejects")
    func groupsAreRebuilt() {
        let narrowed = result().keeping { $0.id != "shop-api" }
        let shop = narrowed.groups.first { $0.project.name == "shop" }

        #expect(narrowed.services.map(\.id) == ["shop-web", "blog", "postgres"])
        #expect(shop?.services.map(\.id) == ["shop-web"])
    }

    @Test("a group that loses every service is dropped rather than left empty")
    func emptiedGroupsAreDropped() {
        let narrowed = result().keeping { $0.id != "blog" }
        #expect(narrowed.groups.map(\.project.name) == ["shop"])
    }

    @Test("standalone services are filtered too")
    func standaloneIsFiltered() {
        let narrowed = result().keeping { $0.id != "postgres" }
        #expect(narrowed.standalone.isEmpty)
        #expect(narrowed.groups.count == 2)
    }

    /// Both describe the machine, not the view, which is why the sidebar footer
    /// can keep counting sockets off a narrowed result.
    @Test("allSockets and hidden are carried through untouched")
    func machineFactsSurvive() {
        let original = result()
        let narrowed = original.keeping { $0.id == "blog" }

        #expect(narrowed.allSockets == original.allSockets)
        #expect(narrowed.hidden == original.hidden)
        #expect(narrowed.services.count == 1)
    }

    /// The fast path scans for the first rejected service and copies the prefix
    /// before it, so dropping the very first one exercises an empty prefix.
    @Test("dropping the first service keeps the rest in order")
    func dropsTheFirstService() {
        let narrowed = result().keeping { $0.id != "shop-web" }
        #expect(narrowed.services.map(\.id) == ["shop-api", "blog", "postgres"])
    }

    @Test("dropping the last service keeps the rest in order")
    func dropsTheLastService() {
        let narrowed = result().keeping { $0.id != "postgres" }
        #expect(narrowed.services.map(\.id) == ["shop-web", "shop-api", "blog"])
    }

    @Test("rejecting everything leaves an empty result with no groups")
    func rejectingEverything() {
        let narrowed = result().keeping { _ in false }
        #expect(narrowed.services.isEmpty)
        #expect(narrowed.groups.isEmpty)
        #expect(narrowed.standalone.isEmpty)
    }
}
