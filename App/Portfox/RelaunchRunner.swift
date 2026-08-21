import Foundation
import PortfoxKit

/// Hands a relaunch script to a terminal.
///
/// A terminal cannot be told "run this", only "open this", so the command is
/// written to an executable file and the file is what gets opened. Terminal,
/// iTerm2 and Warp all run one; `ExternalApp.runsHandedOverScript` records which.
///
/// The scripts go under `FileManager.temporaryDirectory`, which for an unsandboxed
/// app is the per-user `/var/folders/…/T` and not world-writable `/tmp`. Nobody
/// else can read the command or swap the file out between writing and running.
enum RelaunchRunner {
    private static let directoryName = "Portfox-Relaunch"

    @MainActor
    static func run(_ command: RelaunchCommand, in terminal: ExternalApp) async throws {
        let script = try write(command)
        try await ExternalApps.open([script], with: terminal)
    }

    /// Old scripts are cleared at launch rather than after each run. Deleting one
    /// straight after handing it over is a race with the terminal that is about to
    /// read it, and the loser is a restart that silently does nothing.
    static func sweepLeftovers() {
        let manager = FileManager.default
        guard let contents = try? manager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return }
        for script in contents { try? manager.removeItem(at: script) }
    }

    private static func write(_ command: RelaunchCommand) throws -> URL {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)

        // `.command` is the extension Terminal and its imitators recognise as a
        // script to run. Without it the file opens in a text editor.
        let script = directory.appendingPathComponent("restart-\(UUID().uuidString).command")
        try command.script.write(to: script, atomically: true, encoding: .utf8)
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        return script
    }

    private static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(directoryName, isDirectory: true)
    }
}
