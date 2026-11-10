import Foundation
import Testing
@testable import PortfoxKit

@Suite("process inspector")
struct ProcessInspectorTests {
    private let inspector = ProcessInspector()

    @Test("resident memory of the running test process is reported")
    func residentMemoryIsReported() {
        #expect((inspector.taskSample(pid: getpid())?.residentBytes ?? 0) > 0)
    }

    /// The percent maths is unit tested on its own. This is the wiring underneath
    /// it: that `pti_total_user` and `pti_total_system` are read at all, and that
    /// the counter really does climb with work done.
    @Test("cumulative CPU time climbs between two samples of a busy process")
    func cpuTimeClimbs() {
        let first = inspector.taskSample(pid: getpid())
        #expect(first != nil)
        #expect((first?.residentBytes ?? 0) > 0)

        var sink: UInt64 = 0
        for value in 0..<2_000_000 { sink = sink &+ UInt64(value) }
        #expect(sink > 0)

        let second = inspector.taskSample(pid: getpid())
        #expect((second?.cpuNanoseconds ?? 0) > (first?.cpuNanoseconds ?? 0))
    }

    @Test("the skeleton scan carries no executable metadata")
    func skeletonOmitsExecutableMetadata() {
        let skeleton = inspector.processSkeleton()

        #expect(!skeleton.isEmpty)
        #expect(skeleton.allSatisfy { $0.executablePath == nil && $0.arguments.isEmpty })
    }

    @Test("snapshot of a pid nothing occupies returns nil")
    func snapshotOfMissingPidIsNil() {
        #expect(inspector.snapshot(pid: .max) == nil)
    }

    /// The libproc walk against a real accepted connection, inside this process.
    @Test("an accepted connection is reported by its remote port")
    func connectionPeersSeeAcceptedConnection() throws {
        let server = socket(AF_INET, SOCK_STREAM, 0)
        let client = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(server); close(client) }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                bind(server, generic, length) == 0 && listen(server, 1) == 0
                    && getsockname(server, generic, &length) == 0
                    && connect(client, generic, length) == 0
            }
        }
        try #require(bound)
        let accepted = accept(server, nil, nil)
        defer { close(accepted) }

        var local = sockaddr_in()
        var localLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(client, $0, &localLength) }
        }

        let peers = inspector.connectionPeers(pid: getpid(), port: Int(UInt16(bigEndian: address.sin_port)))
        #expect(peers.contains(Int(UInt16(bigEndian: local.sin_port))))
    }

    private func procArgs(_ entries: [String]) -> [UInt8] {
        var buffer = withUnsafeBytes(of: Int32(1)) { Array($0) }
        buffer += Array("/usr/bin/node".utf8) + [0, 0, 0]
        for entry in entries { buffer += Array(entry.utf8) + [0] }
        return buffer
    }

    @Test("the Localfox domain is read from the environment block")
    func localfoxDomainIsRead() {
        let buffer = procArgs(["node", "PATH=/usr/bin", "LOCALFOX_HOST=Wishfox.localhost"])
        #expect(ProcessInspector.localfoxDomain(in: buffer) == "wishfox.localhost")
    }

    @Test("a LOCALFOX_HOST that is not a .localhost host is ignored")
    func foreignDomainIsIgnored() {
        #expect(ProcessInspector.localfoxDomain(in: procArgs(["node", "LOCALFOX_HOST=evil.com"])) == nil)
        #expect(ProcessInspector.localfoxDomain(in: procArgs(["node", "LOCALFOX_HOST=a/b.localhost"])) == nil)
        #expect(ProcessInspector.localfoxDomain(in: procArgs(["node"])) == nil)
    }

    /// A copy, because the kernel withholds a platform binary's environment, and
    /// `/bin/sleep` is one. A dev server's `node` or `bun` is not.
    @Test("a live child's Localfox domain reaches its snapshot")
    func liveChildCarriesLocalfoxDomain() throws {
        let tree = TempTree()
        defer { tree.cleanUp() }
        let sleep = tree.root.appendingPathComponent("sleep")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: sleep)

        let child = Process()
        child.executableURL = sleep
        child.arguments = ["5"]
        child.environment = ["LOCALFOX_HOST": "shop.localhost"]
        try child.run()
        defer { child.terminate() }
        // `run` returns before the child has exec'd, and until then its
        // arguments and environment are still the parent's.
        Thread.sleep(forTimeInterval: 0.2)

        #expect(inspector.snapshot(pid: child.processIdentifier)?.localfoxDomain == "shop.localhost")
    }
}
