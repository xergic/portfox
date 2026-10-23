import Foundation
import PortfoxKit

/// "Notify when it is up". Fires whether or not arrival banners are on,
/// because the user asked for this one by name.
@MainActor
extension AppState {
    func isWaiting(for target: StartTarget) -> Bool { starts.isArmed(target) }

    /// A stopped service pin waits on its port, not its project, so a sibling
    /// service of the same project starting first does not answer for it.
    func waitTarget(of pin: Pin) -> StartTarget {
        switch pin.target {
        case .project(let root): .project(root: root)
        case .service(let key): .port(key.port)
        }
    }

    /// Restarts the loop, so a 60 second sleep does not swallow the first minute
    /// of the wait.
    func toggleWait(for target: StartTarget, label: String) {
        starts.toggle(target, label: label)
        guard starts.isArmed(target) else { return }
        if !notifier.isAuthorized {
            Task { await notifier.requestAuthorization() }
        }
        start()
    }

    /// Expired first, so a Mac that slept through the deadline does not wake to
    /// an "is up" for a wait that should already have ended. Nothing fires while
    /// macOS has not granted banners yet: the first wait is armed at the same
    /// moment the prompt appears, and a fired wait whose banner is dropped is
    /// gone for good.
    func noteStarts(in scan: ScanResult, appeared: [RunningService]) {
        guard starts.isArmed else { return }
        for label in starts.expire() {
            notifier.postGaveUp(waitingFor: label, afterMinutes: StartWatches.timeoutMinutes)
        }
        guard notifier.isAuthorized else { return }
        for service in starts.fire(in: scan, appeared: appeared) {
            notifier.postStarted(named(service))
        }
    }
}
