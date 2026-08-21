import Foundation
import Testing
@testable import PortfoxKit

@Suite("CPU usage")
struct CPUUsageTests {
    private func sample(cpu: UInt64) -> TaskSample {
        TaskSample(residentBytes: 0, cpuNanoseconds: cpu)
    }

    @Test("a second of CPU over a second of wall clock is one core")
    func oneCore() {
        let percent = CPUUsage.percent(
            from: sample(cpu: 0),
            to: sample(cpu: 1_000_000_000),
            over: .seconds(1)
        )
        #expect(percent == 100)
    }

    @Test("a process on four cores reads above 100, as Activity Monitor reports it")
    func multipleCores() {
        let percent = CPUUsage.percent(
            from: sample(cpu: 0),
            to: sample(cpu: 4_000_000_000),
            over: .seconds(1)
        )
        #expect(percent == 400)
    }

    @Test("an idle process reads zero rather than nothing")
    func idle() {
        let percent = CPUUsage.percent(from: sample(cpu: 500), to: sample(cpu: 500), over: .seconds(2))
        #expect(percent == 0)
    }

    @Test("the counter is scaled by the interval, not assumed to be a second")
    func scalesByInterval() {
        let percent = CPUUsage.percent(
            from: sample(cpu: 0),
            to: sample(cpu: 1_000_000_000),
            over: .seconds(5)
        )
        #expect(percent == 20)
    }

    @Test("a fractional reading rounds to a whole percent")
    func rounds() {
        let percent = CPUUsage.percent(from: sample(cpu: 0), to: sample(cpu: 126_000_000), over: .seconds(1))
        #expect(percent == 13)
    }

    /// A recycled pid puts a brand new process's counter next to the old one's.
    @Test("a counter that went backwards reports nothing, not a negative")
    func recycledPID() {
        let percent = CPUUsage.percent(
            from: sample(cpu: 9_000_000_000),
            to: sample(cpu: 12_000),
            over: .seconds(1)
        )
        #expect(percent == nil)
    }

    @Test("two samples taken at the same instant report nothing")
    func zeroInterval() {
        let percent = CPUUsage.percent(from: sample(cpu: 0), to: sample(cpu: 5), over: .zero)
        #expect(percent == nil)
    }

    // MARK: - A whole sample at once

    @Test("every pid present in both samples gets a percent")
    func percentsAcrossPIDs() {
        let percents = CPUUsage.percents(
            from: [1: sample(cpu: 0), 2: sample(cpu: 1_000_000_000)],
            to: [1: sample(cpu: 500_000_000), 2: sample(cpu: 3_000_000_000)],
            over: .seconds(1)
        )
        #expect(percents == [1: 50, 2: 200])
    }

    /// A worker that started since the last tick, or one whose pid was recycled.
    @Test("a pid with nothing to compare against is left out rather than zeroed")
    func unpairedPIDs() {
        let percents = CPUUsage.percents(
            from: [1: sample(cpu: 0)],
            to: [1: sample(cpu: 1_000_000_000), 2: sample(cpu: 400)],
            over: .seconds(1)
        )
        #expect(percents == [1: 100])
    }

    @Test("a pid that has gone since the last sample does not linger")
    func departedPIDs() {
        let percents = CPUUsage.percents(
            from: [1: sample(cpu: 0), 9: sample(cpu: 0)],
            to: [1: sample(cpu: 1_000_000_000)],
            over: .seconds(1)
        )
        #expect(percents == [1: 100])
    }

    @Test("sub-second intervals keep their precision")
    func subSecond() {
        #expect(CPUUsage.nanoseconds(in: .milliseconds(250)) == 250_000_000)
        let percent = CPUUsage.percent(
            from: sample(cpu: 0),
            to: sample(cpu: 250_000_000),
            over: .milliseconds(250)
        )
        #expect(percent == 100)
    }
}
