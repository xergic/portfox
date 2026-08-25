import Foundation
import PortfoxKit

/// What counts as an arrival worth reacting to.
///
/// An extension in its own file, because `AppState` had grown past what one file
/// should hold. The policy lives here and the state lives in `ServiceArrivals`,
/// so the store never has to know what the ignore list is.
@MainActor
extension AppState {
    func noteArrivals(_ appeared: [RunningService], kind: RefreshKind) {
        // Never on a manual Refresh. The user is looking at the list, so washing a
        // row they can already see reads as a bug, and `reloadingFromDisk` is the
        // one path that re-resolves `detection.type`, which moves `primarySocket`
        // and so changes the id of a process that never restarted.
        guard kind != .userRequested else { return }

        arrivals.record(appeared.filter(isWorthAnnouncing))
    }

    /// The first service id the popover would draw, for `--arrived` snapshots.
    var firstServiceID: String? {
        result.groups.first?.services.first?.id ?? result.services.first?.id
    }

    /// System noise never surfaces, and neither does anything the user has
    /// explicitly told Portfox to stop showing them.
    private func isWorthAnnouncing(_ service: RunningService) -> Bool {
        service.classification != .systemNoise && !isIgnored(service)
    }
}
