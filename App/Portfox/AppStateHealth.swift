import Foundation
import PortfoxKit

/// When the HTTP status is read. The reading itself lives in `HealthChecks`.
@MainActor
extension AppState {
    /// Off in a snapshot run, which renders once and exits before any answer could
    /// arrive, so a request would only reach a dev server for nothing.
    private var mayCheckHealth: Bool { checksHealth && SnapshotRenderer.requestedPath == nil }

    func checkHealthOfVisibleServices() {
        guard mayCheckHealth else { return }
        health.check(result.services)
    }

    /// Only what the user can see. A hidden or ignored server is nobody's business
    /// to send a request to.
    func checkHealth(ofArrivals appeared: [RunningService]) {
        guard mayCheckHealth, !appeared.isEmpty else { return }
        let visible = Set(result.services.map(\.id))
        health.check(appeared.filter { visible.contains($0.id) })
    }
}
