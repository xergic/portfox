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
}
