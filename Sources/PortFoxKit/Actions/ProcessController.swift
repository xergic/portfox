import Darwin
import Foundation

/// Stops services.
///
/// Signals are only ever sent to a single pid, never to a process group. A dev
/// server started from a terminal shares its group with the user's shell, so
/// `killpg` would take the shell down with it.
public struct ProcessController: Sendable {
    public enum Outcome: Equatable, Sendable {
        /// The process is gone.
        case exited
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
    public func stop(_ service: RunningService) async -> Outcome {
        let target = service.rootProcess
        if case .refused(let reason) = safetyCheck(target) { return .refused(reason: reason) }

        guard kill(target.pid, SIGTERM) == 0 else { return outcomeForErrno() }

        let deadline = ContinuousClock.now + gracePeriod
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: pollInterval)
            if !inspector.isAlive(pid: target.pid) { return .exited }
        }
        return inspector.isAlive(pid: target.pid) ? .stillRunning : .exited
    }

    /// Sends SIGKILL to the logical root and to any descendant that outlives it.
    /// Only offered after a SIGTERM has already failed.
    public func forceStop(_ service: RunningService, tree: ProcessTree) async -> Outcome {
        let target = service.rootProcess
        if case .refused(let reason) = safetyCheck(target) { return .refused(reason: reason) }

        let descendants = tree.descendants(of: target.pid)
            .filter { safetyCheck($0) == .exited }

        guard kill(target.pid, SIGKILL) == 0 else { return outcomeForErrno() }

        // Children reparent to launchd when their parent dies, so they must be
        // collected from the tree captured before the kill.
        try? await Task.sleep(for: pollInterval)
        for child in descendants where inspector.isAlive(pid: child.pid) {
            _ = kill(child.pid, SIGKILL)
        }

        try? await Task.sleep(for: pollInterval)
        return inspector.isAlive(pid: target.pid) ? .stillRunning : .exited
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
