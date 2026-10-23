import PortfoxKit
import SwiftUI

/// Telling the user when a watched service stops.
///
/// An extension in its own file, because `AppState` had grown past what one file
/// should hold. The list and the stop excuses live in `WatchedServices`, and
/// Start Again shares the relaunch path in `AppStateRestart`.
@MainActor
extension AppState {
    func isWatched(_ service: RunningService) -> Bool { watched.contains(service) }

    /// Same rule as ignoring: a service with nothing durable to key on cannot be
    /// recognised once it is gone.
    func canWatch(_ service: RunningService) -> Bool { canIgnore(service) }

    /// For the context menu and the detail pane, which both offer the toggle.
    func watchBinding(for service: RunningService) -> Binding<Bool> {
        Binding(get: { self.isWatched(service) }, set: { self.setWatched($0, for: service) })
    }

    /// Asks macOS for notifications on the first watch, because the arrival
    /// preference may be off and a watch that can never fire is worse than a prompt.
    func setWatched(_ isWatched: Bool, for service: RunningService) {
        watched.setWatched(isWatched, for: service)
        if isWatched, !notifier.isAuthorized {
            Task { await notifier.requestAuthorization() }
        }
    }

    func noteDepartures(_ departed: [RunningService]) {
        guard !departed.isEmpty else { return }
        for service in watched.unexpected(departed) {
            notifier.postDeparture(of: named(service), offersStartAgain: canRestart && canRelaunch(service))
        }
    }
}
