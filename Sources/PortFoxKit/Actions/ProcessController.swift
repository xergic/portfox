import Darwin
import Foundation

/// Stops services.
///
/// Two rules govern everything here.
///
/// Signals go to a single pid, never to a process group. A dev server started
/// from a terminal shares its group with the user's shell, so `killpg` would
/// take the shell down with it.
///
/// Every signal is preceded by a fresh identity read. A snapshot taken during a
/// scan can be seconds old, and in that window the kernel can hand the same pid
/// to an entirely different process. `kill(pid, 0)` proves only that a pid is
/// occupied, so occupancy is never treated as proof of identity.
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
        /// Already gone, or the pid now hosts a different process.
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
    /// reparent to launchd the moment their parent dies and are then unreachable
    /// through the tree.
    public func stop(_ service: RunningService, tree: ProcessTree? = nil) async -> Outcome {
        let target = service.rootProcess
        let verdict = verify(target)
        guard verdict == .exited else { return verdict }

        let descendants = tree?.descendants(of: target.pid) ?? []
        guard kill(target.pid, SIGTERM) == 0 else { return outcomeForErrno() }

        guard await waitForExit(of: target) else { return .stillRunning }
        return Outcome.exitedLeavingChildren(pids: await sweepOrphans(descendants)).normalised
    }

    /// Sends SIGKILL to the logical root and to any descendant that outlives it.
    /// Only offered after a SIGTERM has already failed.
    public func forceStop(_ service: RunningService, tree: ProcessTree) async -> Outcome {
        let target = service.rootProcess
        let verdict = verify(target)
        guard verdict == .exited else { return verdict }

        let descendants = tree.descendants(of: target.pid)
        let rootSignalled = kill(target.pid, SIGKILL) == 0
        try? await Task.sleep(for: pollInterval)

        // A failure to signal the root is not a reason to leave its orphaned
        // children behind, so the descendant sweep runs either way.
        for child in descendants where verify(child) == .exited {
            _ = kill(child.pid, SIGKILL)
        }

        try? await Task.sleep(for: pollInterval)
        if inspector.isSameProcessAlive(target) { return rootSignalled ? .stillRunning : .notPermitted }
        return .exited
    }

    // MARK: - Safety

    /// Confirms the pid still hosts the process the snapshot describes, then
    /// applies the safety rules to the freshly read process rather than the
    /// stale one. Returns `.exited` when it is safe to signal.
    func verify(_ snapshot: ProcessSnapshot) -> Outcome {
        guard let current = inspector.snapshot(pid: snapshot.pid) else { return .notFound }
        guard current.identity == snapshot.identity else { return .notFound }
        return safetyCheck(current)
    }

    /// Everything PortFox refuses to signal. Returns `.exited` when the process
    /// is safe to signal, which reads oddly but keeps the call sites to a single
    /// comparison.
    func safetyCheck(_ process: ProcessSnapshot) -> Outcome {
        guard process.pid > 1 else { return .refused(reason: "system process") }
        guard process.pid != getpid() else { return .refused(reason: "PortFox itself") }
        guard process.uid == getuid() else { return .notPermitted }
        guard ProcessRole.of(process) != .boundary else {
            return .refused(reason: "shell or terminal session")
        }
        return .exited
    }

    // MARK: - Waiting

    private func waitForExit(of target: ProcessSnapshot) async -> Bool {
        let deadline = ContinuousClock.now + gracePeriod
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: pollInterval)
            if !inspector.isSameProcessAlive(target) { return true }
        }
        return !inspector.isSameProcessAlive(target)
    }

    /// Children that outlive their parent get the same SIGTERM the user asked
    /// for. Anything that survives that is escalated by the user, never here.
    private func sweepOrphans(_ descendants: [ProcessSnapshot]) async -> [pid_t] {
        let orphans = descendants.filter { verify($0) == .exited }
        guard !orphans.isEmpty else { return [] }

        for orphan in orphans { _ = kill(orphan.pid, SIGTERM) }
        try? await Task.sleep(for: gracePeriod)
        return orphans.filter { inspector.isSameProcessAlive($0) }.map(\.pid)
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
