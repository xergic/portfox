import ServiceManagement
import SwiftUI

/// Thin wrapper over `SMAppService`, which reports state through a property that
/// SwiftUI cannot observe directly.
@MainActor
@Observable
final class LaunchAtLogin {
    private(set) var isEnabled: Bool
    private(set) var lastError: String?

    init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            // Registration fails for an unsigned build, which is the normal state
            // during development. Saying so beats a toggle that silently reverts.
            lastError = "macOS refused the change. \(error.localizedDescription)"
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
