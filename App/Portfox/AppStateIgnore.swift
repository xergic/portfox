import Foundation
import PortfoxKit

/// The ignore list. Every change goes through `applyFilters`, so ignoring a
/// service redraws at once rather than on the next tick.
@MainActor
extension AppState {
    var ignoredEntries: [IgnoredService] { ignoredServices.entries }
    /// Anything on the list, running or not. The Preferences inventory.
    var hasIgnoredServices: Bool { !ignoredServices.isEmpty }
    /// Only the ones actually listening. What the dashboard chip can show.
    var hasRunningIgnoredServices: Bool { !ignoredResult.services.isEmpty }

    func isIgnored(_ service: RunningService) -> Bool { ignoredServices.contains(service) }
    func canIgnore(_ service: RunningService) -> Bool { ignoredServices.canIgnore(service) }

    func ignore(_ service: RunningService) {
        ignoredServices.ignore(service)
        applyFilters()
        Telemetry.send(.serviceIgnored(service))
    }

    func stopIgnoring(_ service: RunningService) {
        ignoredServices.stopIgnoring(service)
        applyFilters()
    }

    func stopIgnoring(_ key: ServiceKey) {
        ignoredServices.remove(key)
        applyFilters()
    }
}
