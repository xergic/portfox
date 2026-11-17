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
    static let limitChoices = [30, 60, 120, 240, 480]

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Key.isEnabled)
            if !isEnabled { reset() }
        }
    }

    var limitMinutes: Int {
        didSet { defaults.set(limitMinutes, forKey: Key.limitMinutes) }
    }

    var threshold: Duration { .seconds(limitMinutes * 60) }

    /// Minutes idle by service id, for servers past half the limit. Read by the
    /// rows, so it is written only when a rounded value moves.
    private(set) var idleMinutes: [String: Int] = [:]

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

    private enum Key {
        static let isEnabled = "warnsAboutIdleAgentServers"
        static let limitMinutes = "idleAlertLimitMinutes"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Key.isEnabled: true, Key.limitMinutes: 60])
        isEnabled = defaults.bool(forKey: Key.isEnabled)
        limitMinutes = defaults.integer(forKey: Key.limitMinutes)
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
        let reached = watch.update(readings, elapsed: elapsed, threshold: threshold)
        let minutes = watch.idleMinutes(atLeast: threshold / 2)
        if minutes != idleMinutes { idleMinutes = minutes }
        return reached
    }

    func reset() {
        watch = IdleWatch()
        previous = [:]
        previousAt = nil
        if !idleMinutes.isEmpty { idleMinutes = [:] }
    }
}
