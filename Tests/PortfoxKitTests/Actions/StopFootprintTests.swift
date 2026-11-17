import Foundation
import Testing
@testable import PortfoxKit

@Suite("How much memory a stop gave back")
struct StopFootprintTests {
    private let started = Date(timeIntervalSince1970: 1_000)

    private func process(_ pid: pid_t, parent: pid_t) -> ProcessSnapshot {
        ProcessSnapshot(pid: pid, parentPID: parent, uid: 501, startTime: started)
    }

    private func live(_ pid: pid_t) -> String? { ProcessSnapshot.identity(pid: pid, startTime: started) }

    private var tree: ProcessTree {
        ProcessTree(processes: [process(10, parent: 1), process(11, parent: 10), process(12, parent: 11)])
    }

    private func service(container: ContainerSnapshot? = nil) -> RunningService {
        makeService(port: 3000, project: nil, pid: 10, container: container, startTime: started)
    }

    @Test("the root and every descendant count once")
    func measureCountsRootAndDescendantsOnce() {
        let footprint = StopFootprint.measure(service(), tree: tree, currentIdentity: live) { _ in 100 }

        #expect(footprint.entries.count == 3)
        #expect(footprint.entries.values.reduce(0) { $0 + $1.bytes } == 300)
    }

    @Test("only processes that exited count as freed")
    func freedCountsOnlyExited() {
        let footprint = StopFootprint.measure(service(), tree: tree, currentIdentity: live) { $0 == 10 ? 100 : 50 }

        #expect(footprint.freed { pid, _ in pid != 10 } == 100)
    }

    @Test("a recycled pid is gone, the same process is not")
    func freedSkipsRecycledPid() {
        let footprint = StopFootprint.measure(
            service(), tree: ProcessTree(processes: [process(10, parent: 1)]), currentIdentity: live
        ) { _ in 100 }
        let original = ProcessSnapshot.identity(pid: 10, startTime: started)
        let recycled = ProcessSnapshot.identity(pid: 10, startTime: started.addingTimeInterval(60))

        #expect(footprint.freed { _, identity in identity == recycled } == 100)
        #expect(footprint.freed { _, identity in identity == original } == 0)
    }

    @Test("a pid the tree remembers but another process now holds is not measured")
    func measureSkipsStalePid() {
        let footprint = StopFootprint.measure(
            service(),
            tree: tree,
            currentIdentity: { $0 == 11 ? "11-999" : ProcessSnapshot.identity(pid: $0, startTime: started) },
            sample: { _ in 100 }
        )

        #expect(footprint.entries.keys.sorted() == [10, 12])
    }

    @Test("a container row measures nothing, its forwarder is shared")
    func containerRowMeasuresNothing() {
        let container = ContainerSnapshot(id: "web", name: "web", image: "nginx:alpine")
        let footprint = StopFootprint.measure(service(container: container), tree: tree, currentIdentity: live) { _ in 100 }

        #expect(footprint.entries.isEmpty)
    }
}
