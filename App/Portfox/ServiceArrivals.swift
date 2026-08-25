import Foundation
import PortfoxKit

/// Which services just appeared, and whether that is worth telling the user.
///
/// One diff, two consumers. The flash keeps ids, so a row reads its own state the
/// way it already reads `isBusy`. The notification consumes the services outright,
/// because it needs their names and ports and has nothing to remember afterwards.
@MainActor
@Observable
final class ServiceArrivals {
    /// Rows to wash green. Deliberately not intersected with the live set the way
    /// `stubbornServiceIDs` is: a service that appears and dies inside the flash
    /// window leaves a dead id here for a moment and nothing renders it, because
    /// the flash is a property an existing row reads and never a row it inserts.
    /// That is how "no lingering closed rows" falls out for free.
    private(set) var recentIDs: Set<String> = []

    let notifier = ArrivalNotifier()

    /// The first scan diffs against an empty result, so every listener on the
    /// machine reads as new. Per instance rather than persisted, which is also
    /// what keeps the snapshot renderer's second `AppState` silent: it scans once
    /// and exits, so this is never true there.
    private var hasSettled = false

    private var decayTask: Task<Void, Never>?
    private static let flashDuration = Duration.seconds(4)

    /// Ports Portfox was asked to bring back, and when the promise expires.
    ///
    /// `busyServiceIDs` cannot stand in. It is cleared when `restart` returns, and
    /// a relaunched server has not bound its port by then, because the command was
    /// handed to a terminal and boot takes seconds. The id in it would be the old
    /// one in any case: a restart gives the process a new pid and start time, so
    /// the row that comes back is genuinely new to any id diff.
    private var expectedReturns: [Int: ContinuousClock.Instant] = [:]
    private static let returnWindow = Duration.seconds(90)

    func isRecent(_ service: RunningService) -> Bool { recentIDs.contains(service.id) }

    /// Called on every successful scan, including one that moved nothing, which is
    /// what lets a machine with no listeners at launch still settle.
    func record(_ arrivals: [RunningService]) {
        guard hasSettled else {
            hasSettled = true
            return
        }
        guard !arrivals.isEmpty else { return }

        let expected = consumeExpectedReturns(matching: arrivals)

        flash(Set(arrivals.map(\.id)))

        // A restart flashes but does not notify. The user asked for it, the app is
        // probably in front of them, and the green row is the confirmation.
        let unexpected = arrivals.filter { !expected.contains($0.id) }
        guard notifier.isEnabled, let digest = ServiceArrivalDigest(unexpected) else { return }
        notifier.post(digest)
    }

    /// Recorded before anything is signalled, so a server that comes straight back
    /// is already accounted for by the time the scan notices it.
    func expectReturn(of service: RunningService) {
        let deadline = ContinuousClock.now + Self.returnWindow
        for socket in service.sockets { expectedReturns[socket.port] = deadline }
    }

    /// Snapshots only. `Task.sleep` never fires under `ImageRenderer` and the
    /// snapshot process exits, so this sets the state without arming the decay.
    func force(_ id: String) { recentIDs = [id] }

    var dashboardRequests: Int { notifier.dashboardRequests }

    // MARK: - Internals

    private func consumeExpectedReturns(matching arrivals: [RunningService]) -> Set<String> {
        let now = ContinuousClock.now
        expectedReturns = expectedReturns.filter { $0.value > now }

        var matched: Set<String> = []
        for service in arrivals where expectedReturns[service.port] != nil {
            matched.insert(service.id)
            expectedReturns.removeValue(forKey: service.port)
        }
        return matched
    }

    /// One task for the whole set rather than one per row. A second arrival inside
    /// the window restarts the clock and extends the first row's flash, which
    /// costs something only for a steady stream of arrivals, and arrivals are rare.
    private func flash(_ ids: Set<String>) {
        recentIDs.formUnion(ids)
        decayTask?.cancel()
        decayTask = Task { [weak self] in
            try? await Task.sleep(for: Self.flashDuration)
            guard !Task.isCancelled, let self, !recentIDs.isEmpty else { return }
            recentIDs = []
        }
    }
}
