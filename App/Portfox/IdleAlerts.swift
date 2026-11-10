import Foundation
import Observation
import PortfoxKit

/// "Warn about idle agent servers": the preference, and what the last sample
/// looked like so the next one can be measured against it.
///
/// On by default for the same reason as memory warnings: it never prompts, and
/// it never stops anything. The banner asks, and the user decides.
@MainActor
@Observable
final class IdleAlerts {
    static let threshold = Duration.seconds(60 * 60)

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.defaultsKey)
            if !isEnabled { reset() }
        }
    }

    @ObservationIgnored private var watch = IdleWatch()
    /// Its own previous sample, because `ProcessMetrics` keeps one only while
    /// the CPU column is on, and this has to work with it off.
    @ObservationIgnored private var previous: [pid_t: TaskSample] = [:]
    /// Suspending, so the hours a Mac spends asleep never count as idle time.
    @ObservationIgnored private var previousAt: SuspendingClock.Instant?
    /// A few syscalls per agent server per tick, cheap enough not to need the
    /// repository's actor.
    let inspector = ProcessInspector()
    private let defaults: UserDefaults
    private static let defaultsKey = "warnsAboutIdleAgentServers"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Self.defaultsKey: true])
        isEnabled = defaults.bool(forKey: Self.defaultsKey)
    }

    /// Percent of a core by pid since the previous sample, and how long ago that was.
    func measure(_ sampled: [pid_t: TaskSample]) -> (percents: [pid_t: Int], elapsed: Duration) {
        let now = SuspendingClock.now
        defer {
            previous = sampled
            previousAt = now
        }
        guard let previousAt else { return ([:], .zero) }
        let elapsed = previousAt.duration(to: now)
        return (CPUUsage.percents(from: previous, to: sampled, over: elapsed), elapsed)
    }

    func idle(_ readings: [String: IdleWatch.Reading], elapsed: Duration) -> [String] {
        watch.update(readings, elapsed: elapsed, threshold: Self.threshold)
    }

    func reset() {
        watch = IdleWatch()
        previous = [:]
        previousAt = nil
    }
}
