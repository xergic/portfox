import Foundation
import Testing
@testable import PortfoxKit

@Suite("Watched services that stopped")
struct ScanResultDeparturesTests {
    private func result(_ services: [RunningService]) -> ScanResult {
        ScanResult(services: services, groups: [], standalone: services, allSockets: [], hidden: [])
    }

    private func service(port: Int, pid: pid_t) -> RunningService {
        makeService(port: port, project: nil, pid: pid, executable: "/usr/local/bin/node", id: "\(pid)-\(port)")
    }

    private func key(_ service: RunningService) -> ServiceKey { ServiceKey(service)! }

    @Test("a watched service that is gone is reported")
    func watchedDeparture() {
        let web = service(port: 3000, pid: 10)
        let before = result([web, service(port: 5432, pid: 20)])
        let after = result([service(port: 5432, pid: 20)])

        #expect(after.departed(since: before, watching: [key(web)]).map(\.port) == [3000])
    }

    @Test("an unwatched service that is gone is not reported")
    func unwatchedDeparture() {
        let web = service(port: 3000, pid: 10)
        let database = service(port: 5432, pid: 20)

        #expect(result([database]).departed(since: result([web, database]), watching: [key(database)]).isEmpty)
    }

    /// A restart binds the same port under a new pid, so its id changes while
    /// its key does not. That is the user's server still running.
    @Test("a restart under a new pid is not a departure")
    func restartIsNotDeparture() {
        let before = service(port: 3000, pid: 10)
        let after = service(port: 3000, pid: 11)

        #expect(result([after]).departed(since: result([before]), watching: [key(before)]).isEmpty)
    }
}
