import Foundation
import Testing
@testable import PortfoxKit

@Suite("When an idle banner fires")
struct IdleWatchTests {
    private let hour = Duration.seconds(3600)
    private let minute = Duration.seconds(60)
    private let quiet = IdleWatch.Reading(cpuPercent: 0, peers: [])

    private func run(_ watch: inout IdleWatch, _ reading: IdleWatch.Reading, minutes: Int) -> [String] {
        var fired: [String] = []
        for _ in 0..<minutes {
            fired += watch.update(["next": reading], elapsed: minute, threshold: hour)
        }
        return fired
    }

    @Test("an hour of nothing fires once")
    func quietHourFiresOnce() {
        var watch = IdleWatch()
        _ = watch.update(["next": quiet], elapsed: .zero, threshold: hour)

        #expect(run(&watch, quiet, minutes: 59).isEmpty)
        #expect(run(&watch, quiet, minutes: 1) == ["next"])
        #expect(run(&watch, quiet, minutes: 120).isEmpty)
    }

    @Test("CPU use resets the clock")
    func cpuResets() {
        var watch = IdleWatch()
        _ = watch.update(["next": quiet], elapsed: .zero, threshold: hour)
        _ = run(&watch, quiet, minutes: 50)
        _ = run(&watch, IdleWatch.Reading(cpuPercent: 4, peers: []), minutes: 1)

        #expect(run(&watch, quiet, minutes: 59).isEmpty)
    }

    @Test("a new connection resets the clock, a connection held open does not")
    func newPeerResets() {
        var watch = IdleWatch()
        let tab = IdleWatch.Reading(cpuPercent: 0, peers: [51_000])
        _ = watch.update(["next": tab], elapsed: .zero, threshold: hour)

        #expect(run(&watch, tab, minutes: 60) == ["next"])

        var fresh = IdleWatch()
        _ = fresh.update(["next": tab], elapsed: .zero, threshold: hour)
        _ = run(&fresh, tab, minutes: 50)
        _ = run(&fresh, IdleWatch.Reading(cpuPercent: 0, peers: [51_000, 51_007]), minutes: 1)
        #expect(run(&fresh, tab, minutes: 59).isEmpty)
    }

    @Test("busy after the banner arms it again")
    func busyRearms() {
        var watch = IdleWatch()
        _ = watch.update(["next": quiet], elapsed: .zero, threshold: hour)
        _ = run(&watch, quiet, minutes: 60)
        _ = run(&watch, IdleWatch.Reading(cpuPercent: 30, peers: []), minutes: 1)

        #expect(run(&watch, quiet, minutes: 60) == ["next"])
    }

    @Test("the first sample of a server never counts as idle time")
    func firstSampleStartsTheClock() {
        var watch = IdleWatch()
        #expect(watch.update(["next": quiet], elapsed: hour * 2, threshold: hour).isEmpty)
        #expect(run(&watch, quiet, minutes: 59).isEmpty)
    }
}
