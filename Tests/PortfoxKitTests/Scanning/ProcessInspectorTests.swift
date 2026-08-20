import Foundation
import Testing
@testable import PortfoxKit

@Suite("process inspector")
struct ProcessInspectorTests {
    private let inspector = ProcessInspector()

    @Test("resident memory of the running test process is reported")
    func residentMemoryIsReported() {
        #expect((inspector.residentMemory(pid: getpid()) ?? 0) > 0)
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
