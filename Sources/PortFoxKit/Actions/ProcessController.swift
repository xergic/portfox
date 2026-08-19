import Darwin
import Foundation

/// Stops services.
///
/// Signals are only ever sent to a single pid, never to a process group. A dev
/// server started from a terminal shares its group with the user's shell, so
/// `killpg` would take the shell down with it.
public struct ProcessController: Sendable {
    public enum Outcome: Equatable, Sendable {
        /// The process is gone, and so is everything it started.
        case exited
        /// The process is gone but some of its children ignored SIGTERM and have
        /// reparented to launchd. Their pids are reported so the user can deal
        /// with them, since the service row itself is about to disappear.
        case exitedLeavingChildren(pids: [pid_t])
        /// The signal was delivered but the process is still alive. Offer Force Stop.
        case stillRunning
        /// Owned by another user, or otherwise not ours to signal.
        case notPermitted
        case notFound
        /// Refused by PortFox itself because signalling it would be unsafe.
        case refused(reason: String)
    }

    private let inspector: ProcessInspector
    private let gracePeriod: Duration
    private let pollInterval: Duration

    public init(
        inspector: ProcessInspector = ProcessInspector(),
        gracePeriod: Duration = .seconds(3),
        pollInterval: Duration = .milliseconds(150)
    ) {
        self.inspector = inspector
        self.gracePeriod = gracePeriod
        self.pollInterval = pollInterval
    }

    /// Sends SIGTERM to the service's logical root and waits up to the grace
    /// period for it to exit.
    ///
    /// The descendant list is captured before the signal, because children
    /// reparent to launchd the moment their parent dies and are then
    /// unreachable through the tree.
    public func stop(_ service: RunningService, tree: ProcessTree? = nil) async -> Outcome {
        let target = service.rootProcess
        if case .refused(let reason) = safetyCheck(target) { return .refused(reason: reason) }

        let descendants = tree?.descendants(of: target.pid).filter { safetyCheck($0) == .exited } ?? []
        guard kill(target.pid, SIGTERM) == 0 else { return outcomeForErrno() }

        let deadline = ContinuousClock.now + gracePeriod
        var rootExited = false
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: pollInterval)
            if !inspector.isAlive(pid: target.pid) {
                rootExited = true
                break
            }
        }

        guard rootExited || !inspector.isAlive(pid: target.pid) else { return .stillRunning }

        return .exitedLeavingChildren(pids: await sweepOrphans(of: descendants))
            .normalised
    }

    /// Children that outlive their parent get the same SIGTERM the user asked
    /// for. Anything that survives that is escalated by the user, never here.
    private func sweepOrphans(of descendants: [ProcessSnapshot]) async -> [pid_t] {
        let orphans = descendants.filter { inspector.isAlive(pid: $0.pid) }
        guard !orphans.isEmpty else { return [] }

        for orphan in orphans { _ = kill(orphan.pid, SIGTERM) }
        try? await Task.sleep(for: gracePeriod)
        return orphans.map(\.pid).filter { inspector.isAlive(pid: $0) }
    }

    /// Sends SIGKILL to the logical root and to any descendant that outlives it.
    /// Only offered after a SIGTERM has already failed.
    public func forceStop(_ service: RunningService, tree: ProcessTree) async -> Outcome {
        let target = service.rootProcess
        if case .refused(let reason) = safetyCheck(target) { return .refused(reason: reason) }

        let descendants = tree.descendants(of: target.pid)
            .filter { safetyCheck($0) == .exited }

        // A failure to signal the root is not a reason to leave its orphaned
        // children behind, so the descendant sweep runs either way.
        let rootSignalled = kill(target.pid, SIGKILL) == 0
        try? await Task.sleep(for: pollInterval)
        for child in descendants where inspector.isAlive(pid: child.pid) {
            _ = kill(child.pid, SIGKILL)
        }

        try? await Task.sleep(for: pollInterval)
        if inspector.isAlive(pid: target.pid) { return rootSignalled ? .stillRunning : .notPermitted }
        return .exited
    }

    /// Everything PortFox refuses to signal. Returns `.exited` when the process is
    /// safe to signal, which reads oddly but keeps this a single comparison at the
    /// call sites above.
    func safetyCheck(_ process: ProcessSnapshot) -> Outcome {
        guard process.pid > 1 else { return .refused(reason: "system process") }
        guard process.pid != getpid() else { return .refused(reason: "PortFox itself") }
        guard process.uid == getuid() else { return .notPermitted }
        guard ProcessRole.of(process) != .boundary else {
            return .refused(reason: "shell or terminal session")
        }
        return .exited
    }

    private func outcomeForErrno() -> Outcome {
        switch errno {
        case EPERM: .notPermitted
        case ESRCH: .notFound
        default: .stillRunning
        }
    }
}

private extension ProcessController.Outcome {
    /// An empty orphan list is a plain exit.
    var normalised: ProcessController.Outcome {
        if case .exitedLeavingChildren(let pids) = self, pids.isEmpty { return .exited }
        return self
    }
}
