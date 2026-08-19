import Foundation
import Testing
@testable import PortFoxKit

@Suite("process inspector")
struct ProcessInspectorTests {
    private let inspector = ProcessInspector()

    @Test("snapshot of the running test process reports resident memory")
    func snapshotReportsResidentMemory() {
        let snapshot = inspector.snapshot(pid: getpid())

        #expect((snapshot?.residentMemory ?? 0) > 0)
    }

    @Test("the skeleton scan leaves resident memory unset")
    func skeletonOmitsResidentMemory() {
        let skeleton = inspector.processSkeleton()

        #expect(!skeleton.isEmpty)
        #expect(skeleton.allSatisfy { $0.residentMemory == nil })
    }

    @Test("snapshot of a pid nothing occupies returns nil")
    func snapshotOfMissingPidIsNil() {
        #expect(inspector.snapshot(pid: .max) == nil)
    }
}
