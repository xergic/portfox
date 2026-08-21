import AppKit
import Foundation
import PortfoxKit

/// Pointing another app at a service's directory.
///
/// An extension in its own file, because `AppState` had grown past what one file
/// should hold. Nothing here reads the scan, only the two app preferences.
@MainActor
extension AppState {
    var editorApp: ExternalApp? { ExternalApps.editor(id: editorBundleID) }
    var terminalApp: ExternalApp? { ExternalApps.terminal(id: terminalBundleID) }

    /// Restart needs a terminal that runs a script it is handed. Everything else
    /// gets Copy Command, which is honest about what Portfox can actually do.
    var canRestart: Bool { terminalApp?.runsHandedOverScript == true }

    /// An editor opens the repository, so a service deep in a monorepo does not
    /// open as a lone package with no history and no siblings.
    func openInEditor(_ service: RunningService) {
        guard let editor = editorApp else { return }
        guard let directory = service.project?.root ?? service.revealDirectory else { return }
        launch([directory], with: editor)
    }

    /// A terminal opens where the process actually runs, which is the directory
    /// its command expects.
    func openInTerminal(_ service: RunningService) {
        guard let terminal = terminalApp, let directory = service.revealDirectory else { return }
        launch([directory], with: terminal)
    }

    private func launch(_ urls: [URL], with app: ExternalApp) {
        Task {
            do {
                try await ExternalApps.open(urls, with: app)
            } catch {
                report("Could not open \(app.name). \(error.localizedDescription)")
            }
        }
    }
}
