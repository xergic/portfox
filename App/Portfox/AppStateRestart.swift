import Foundation
import PortfoxKit

/// Bringing a service back after stopping it.
///
/// An extension in its own file, because `AppState` had grown past what one file
/// should hold. The relaunch itself lives in `RelaunchCommand`; this is only the
/// order of operations around it.
@MainActor
extension AppState {

    /// Stops the service, then hands its own command line to a terminal.
    ///
    /// The relaunch is built before anything is signalled. Stopping a server and
    /// only then discovering it cannot be brought back is the one outcome worth
    /// designing away.
    func restart(_ service: RunningService) async {
        guard let terminal = relaunchTerminal(for: service), let command = relaunchCommand(for: service) else { return }

        arrivals.expectReturn(of: service)
        markStopping(service)
        defer { clearBusy(service) }

        let tree = await repository.processTree()
        let outcome = await controller.stop(service, tree: tree)
        let problem = record(outcome, for: service)

        // Never relaunch onto a port that is still held. Two servers fighting over
        // one socket is a worse afternoon than a restart that did not happen.
        guard outcome.didStop else {
            await refresh(.afterAction)
            report(problem ?? "\(service.displayName) did not stop, so it was not restarted.")
            return
        }

        let launchProblem = await launch(command, for: service, in: terminal)
        await refresh(.afterAction)
        if let message = launchProblem ?? problem { report(message) }
    }

    /// Relaunches a service that already died, from the argv it was last seen
    /// with. Unlike `restart` there is nothing to stop first.
    func startAgain(_ service: RunningService) async {
        guard let terminal = relaunchTerminal(for: service), let command = relaunchCommand(for: service) else { return }
        arrivals.expectReturn(of: service)
        if let problem = await launch(command, for: service, in: terminal) { report(problem) }
    }

    /// Returns what went wrong, for the caller to report after its refresh. A
    /// successful refresh clears `lastError`, so reporting here would be lost.
    private func launch(_ command: RelaunchCommand, for service: RunningService, in terminal: ExternalApp) async -> String? {
        do {
            try await RelaunchRunner.run(command, in: terminal)
            Telemetry.send(.serviceRestarted(service))
            return nil
        } catch {
            return "\(service.displayName) could not be started again. \(error.localizedDescription)"
        }
    }

    private func relaunchTerminal(for service: RunningService) -> ExternalApp? {
        guard let terminal = terminalApp, terminal.runsHandedOverScript else {
            let name = terminalApp?.name ?? "This terminal"
            report("\(name) cannot be asked to run a command, "
                + "so Portfox cannot restart \(service.displayName).")
            return nil
        }
        return terminal
    }

    /// For a terminal that cannot be handed a script: stop the service and leave
    /// the command on the pasteboard, so bringing it back is one paste.
    func stopAndCopyCommand(_ service: RunningService) async {
        guard let command = relaunchCommand(for: service) else { return }
        copy(command.clipboardText)
        await stop(service)
    }

    /// Whether a Restart or a Copy Command would have anything to offer, so a
    /// service that cannot come back never shows an item that would only explain
    /// itself after being pressed.
    func canRelaunch(_ service: RunningService) -> Bool {
        if case .success = RelaunchCommand.make(for: service) { return true }
        return false
    }

    private func relaunchCommand(for service: RunningService) -> RelaunchCommand? {
        switch RelaunchCommand.make(for: service) {
        case .success(let command):
            return command
        case .failure(let refusal):
            report("Portfox cannot restart \(service.displayName) because \(refusal.reason).")
            return nil
        }
    }
}
