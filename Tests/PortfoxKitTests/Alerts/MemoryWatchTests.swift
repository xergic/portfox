import Foundation
import Testing
@testable import PortfoxKit

@Suite("When a memory banner fires")
struct MemoryWatchTests {
    private let gb: UInt64 = 1 << 30
    private var limits: MemoryWatch.Limits { .init(perService: 4 * gb, total: 12 * gb) }

    @Test("a server crossing its limit fires once")
    func crossingFiresOnce() {
        var watch = MemoryWatch()

        #expect(watch.update(.init(byService: ["next": 3 * gb], total: 3 * gb), limits: limits).isEmpty)
        #expect(watch.update(.init(byService: ["next": 5 * gb], total: 5 * gb), limits: limits) == [.service(id: "next", bytes: 5 * gb)])
        #expect(watch.update(.init(byService: ["next": 6 * gb], total: 6 * gb), limits: limits).isEmpty)
    }

    @Test("hovering just under the limit does not fire again")
    func hoveringDoesNotRefire() {
        var watch = MemoryWatch()
        _ = watch.update(.init(byService: ["next": 4 * gb], total: 4 * gb), limits: limits)

        let justUnder = 4 * gb - gb / 10
        #expect(watch.update(.init(byService: ["next": justUnder], total: justUnder), limits: limits).isEmpty)
        #expect(watch.update(.init(byService: ["next": 4 * gb], total: 4 * gb), limits: limits).isEmpty)
    }

    @Test("falling well below the limit rearms it")
    func fallingBackRearms() {
        var watch = MemoryWatch()
        _ = watch.update(.init(byService: ["next": 5 * gb], total: 5 * gb), limits: limits)
        _ = watch.update(.init(byService: ["next": 2 * gb], total: 2 * gb), limits: limits)

        #expect(watch.update(.init(byService: ["next": 5 * gb], total: 5 * gb), limits: limits) == [.service(id: "next", bytes: 5 * gb)])
    }

    @Test("a server that stopped and came back under the same id fires again")
    func goneServiceIsForgotten() {
        var watch = MemoryWatch()
        _ = watch.update(.init(byService: ["next": 5 * gb], total: 5 * gb), limits: limits)
        _ = watch.update(.init(byService: [:], total: 0), limits: limits)

        #expect(watch.update(.init(byService: ["next": 5 * gb], total: 5 * gb), limits: limits) == [.service(id: "next", bytes: 5 * gb)])
    }

    @Test("the total fires on its own, once")
    func totalFiresOnce() {
        var watch = MemoryWatch()
        let usage = ["a": 3 * gb, "b": 3 * gb, "c": 3 * gb, "d": 3 * gb]

        #expect(watch.update(.init(byService: usage, total: 12 * gb), limits: limits) == [.total(bytes: 12 * gb)])
        #expect(watch.update(.init(byService: usage, total: 13 * gb), limits: limits).isEmpty)
    }

    @Test("a service counts its workers, and the total counts a shared pid once")
    func usageRollsUpWorkers() {
        let web = makeService(port: 3000, project: nil, pid: 10, id: "web")
        let docs = makeService(port: 3001, project: nil, pid: 20, id: "docs")
        let sampled: [pid_t: TaskSample] = [
            10: TaskSample(residentBytes: 1 * gb, cpuNanoseconds: 0),
            11: TaskSample(residentBytes: 2 * gb, cpuNanoseconds: 0),
            20: TaskSample(residentBytes: 1 * gb, cpuNanoseconds: 0)
        ]

        let usage = MemoryWatch.Usage(of: [web, docs], workers: [10: [11], 20: [11]], sampled: sampled)

        #expect(usage.byService == ["web": 3 * gb, "docs": 3 * gb])
        #expect(usage.total == 4 * gb)
    }
}
