import Foundation
import Testing
@testable import PortfoxKit

@Suite("Network exposure")
struct NetworkExposureTests {
    private func service(_ hosts: [(host: String, port: Int)]) -> RunningService {
        makeService(port: hosts[0].port, project: nil, hosts: hosts)
    }

    @Test("a loopback-only service is not exposed")
    func loopback() {
        #expect(service([("127.0.0.1", 3000), ("::1", 3000)]).networkPort == nil)
    }

    /// The scanner records lsof's `*` as `0.0.0.0`.
    @Test("a wildcard bind is exposed on its port")
    func wildcard() {
        #expect(service([("0.0.0.0", 5173)]).networkPort == 5173)
    }

    @Test("an exposed secondary port is offered when the primary is loopback")
    func secondary() {
        #expect(service([("127.0.0.1", 3000), ("192.168.1.20", 3001)]).networkPort == 3001)
    }

    @Test("a service that does not speak HTTP has no network URL")
    func nonHTTP() {
        #expect(service([("0.0.0.0", 5432)]).networkURL(macAddress: "192.168.1.5") == nil)
    }

    @Test("a wildcard bind is reached on the Mac's address")
    func wildcardAddress() {
        #expect(service([("0.0.0.0", 5432)]).networkAddress(macAddress: "192.168.1.5") == "192.168.1.5:5432")
    }

    /// A server bound to one interface answers there alone, and the Mac's
    /// preferred address may belong to another interface.
    @Test("a server bound to one interface keeps that address")
    func specificBind() {
        #expect(service([("10.0.0.2", 3000)]).networkAddress(macAddress: "192.168.1.2") == "10.0.0.2:3000")
    }
}
