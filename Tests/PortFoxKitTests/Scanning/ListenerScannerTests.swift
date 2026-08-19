import Foundation
import Testing
@testable import PortFoxKit

@Suite("lsof output parsing")
struct ListenerScannerTests {
    @Test("parses a process set with several file sets")
    func parsesMultipleSockets() {
        let output = """
        p739
        R1
        cworkerd
        f18
        tIPv4
        n127.0.0.1:57801
        f19
        tIPv4
        n127.0.0.1:51171
        """

        let sockets = ListenerScanner.parse(output)

        #expect(sockets.count == 2)
        #expect(sockets.allSatisfy { $0.pid == 739 })
        #expect(sockets.map(\.port) == [57801, 51171])
    }

    @Test("carries the address family per file set, not per process")
    func tracksFamilyPerSocket() {
        let output = """
        p1017
        crapportd
        f10
        tIPv4
        n*:56940
        f14
        tIPv6
        n*:56940
        """

        let sockets = ListenerScanner.parse(output)

        #expect(sockets.map(\.family) == [.ipv4, .ipv6])
    }

    @Test("resets the family when a new process set starts")
    func resetsFamilyBetweenProcesses() {
        let output = """
        p1
        cfirst
        f1
        tIPv6
        n[::1]:3000
        p2
        csecond
        f1
        n127.0.0.1:4000
        """

        let sockets = ListenerScanner.parse(output)

        #expect(sockets.map(\.family) == [.ipv6, .ipv4])
    }

    @Test(
        "parses every address shape lsof emits",
        arguments: [
            ("127.0.0.1:3000", "127.0.0.1", 3000),
            ("[::1]:50041", "::1", 50041),
            ("*:5000", "0.0.0.0", 5000),
            ("[fe80::1%en0]:8080", "fe80::1%en0", 8080)
        ]
    )
    func parsesAddress(raw: String, host: String, port: Int) {
        let parsed = ListenerScanner.parseAddress(raw)

        #expect(parsed?.host == host)
        #expect(parsed?.port == port)
    }

    @Test("rejects addresses without a numeric port")
    func rejectsMalformedAddress() {
        #expect(ListenerScanner.parseAddress("127.0.0.1") == nil)
        #expect(ListenerScanner.parseAddress("[::1]") == nil)
        #expect(ListenerScanner.parseAddress("localhost:http") == nil)
    }

    @Test("ignores file sets that appear before any process line")
    func ignoresOrphanSockets() {
        #expect(ListenerScanner.parse("f10\ntIPv4\nn127.0.0.1:3000").isEmpty)
    }
}
