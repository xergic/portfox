import Foundation

/// One `proc_taskinfo` read: what a process holds in memory, and how much CPU it
/// has burned since it started.
public struct TaskSample: Sendable, Equatable {
    public let residentBytes: UInt64
    /// Cumulative user plus system time. A counter, not a rate, so a reading only
    /// means something next to an earlier one.
    public let cpuNanoseconds: UInt64

    public init(residentBytes: UInt64, cpuNanoseconds: UInt64) {
        self.residentBytes = residentBytes
        self.cpuNanoseconds = cpuNanoseconds
    }
}

/// Turns two cumulative CPU counters into the rate between them.
public enum CPUUsage {
    /// Percent of a single core, which is what Activity Monitor reports, so a
    /// process saturating four cores reads 400 rather than 100.
    ///
    /// Nil rather than zero whenever the pair cannot be trusted: no elapsed time,
    /// or a counter that went backwards, which is what a recycled pid looks like.
    public static func percent(
        from previous: TaskSample,
        to current: TaskSample,
        over interval: Duration
    ) -> Int? {
        guard current.cpuNanoseconds >= previous.cpuNanoseconds else { return nil }
        let elapsed = nanoseconds(in: interval)
        guard elapsed > 0 else { return nil }

        let burned = Double(current.cpuNanoseconds - previous.cpuNanoseconds)
        let percent = burned / elapsed * 100
        guard percent.isFinite else { return nil }
        return Int(percent.rounded())
    }

    /// Every pid present in both samples, as a percent. A pid seen for the first
    /// time is absent rather than zero, because one reading of a counter says only
    /// how much work a process has ever done.
    public static func percents(
        from previous: [pid_t: TaskSample],
        to current: [pid_t: TaskSample],
        over interval: Duration
    ) -> [pid_t: Int] {
        var percents: [pid_t: Int] = [:]
        percents.reserveCapacity(current.count)
        for (pid, sample) in current {
            guard let earlier = previous[pid],
                  let percent = percent(from: earlier, to: sample, over: interval)
            else { continue }
            percents[pid] = percent
        }
        return percents
    }

    static func nanoseconds(in interval: Duration) -> Double {
        let (seconds, attoseconds) = interval.components
        return Double(seconds) * 1_000_000_000 + Double(attoseconds) / 1_000_000_000
    }
}
