import Foundation
import Testing
@testable import PortfoxKit

@Suite("What appeared since the last scan")
struct ScanResultDiffTests {
    private func result(visible: [RunningService], hidden: [RunningService] = []) -> ScanResult {
        ScanResult(services: visible, groups: [], standalone: visible, allSockets: [], hidden: hidden)
    }

    private func service(port: Int, pid: pid_t = 1, version: String? = nil) -> RunningService {
        var built = makeService(port: port, project: nil, pid: pid, id: "\(pid)-\(port)")
        built.version = version
        return built
    }

    /// The burst the cold-start latch in `ServiceArrivals` exists to swallow.
    /// `rawResult` starts empty, so the first scan of any machine looks like this.
    @Test("the first scan reports every listener as new")
    func firstScanReportsEverything() {
        let scan = result(visible: [service(port: 3000), service(port: 5432), service(port: 6379)])

        #expect(scan.appeared(since: .empty).count == 3)
    }

    @Test("an unchanged scan reports nothing")
    func unchangedScanReportsNothing() {
        let scan = result(visible: [service(port: 3000), service(port: 5432)])

        #expect(scan.appeared(since: scan).isEmpty)
    }

    /// A relaunched server binds the same port under a new pid, so its id is
    /// genuinely new. Nothing in a diff can tell that from a stranger, which is
    /// why a restart is suppressed by port and not by id.
    @Test("a restart reads as exactly one arrival")
    func restartIsOneArrival() {
        let before = result(visible: [service(port: 3000, pid: 100)])
        let after = result(visible: [service(port: 3000, pid: 200)])

        let appeared = after.appeared(since: before)

        #expect(appeared.count == 1)
        #expect(appeared[0].id == "200-3000")
    }

    /// Flipping "Show all listeners" moves the system rows between `services` and
    /// `hidden` without anything binding a port. Diffing the visible list alone
    /// would turn one preference toggle into a burst of arrivals.
    @Test("a service moving between visible and hidden is not an arrival")
    func filterToggleIsNotAnArrival() {
        let noise = service(port: 7000)
        let filtered = result(visible: [service(port: 3000)], hidden: [noise])
        let unfiltered = result(visible: [service(port: 3000), noise])

        #expect(unfiltered.appeared(since: filtered).isEmpty)
        #expect(filtered.appeared(since: unfiltered).isEmpty)
    }

    /// A manual Refresh drops every cache and can re-resolve a version, so the
    /// two results compare unequal while nothing started.
    @Test("a re-resolved version is not an arrival")
    func versionChangeIsNotAnArrival() {
        let before = result(visible: [service(port: 3000)])
        let after = result(visible: [service(port: 3000, version: "20.1")])

        #expect(after != before)
        #expect(after.appeared(since: before).isEmpty)
    }
}
