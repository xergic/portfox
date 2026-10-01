import Foundation

/// Where software that is not the user's own code lives. Every check takes a
/// path and lowercases it itself, so callers cannot disagree about case.
enum SystemPaths {
    static let home = FileManager.default.homeDirectoryForCurrentUser.path.lowercased()

    /// Menu bar apps, editors and Electron helpers all listen on local ports for
    /// their own reasons, and their executable always lives inside a bundle.
    static func isInsideAppBundle(_ path: String) -> Bool {
        path.lowercased().contains(".app/contents/")
    }

    /// Apple's daemons and agents. A session owner, never a task runner.
    static func isSystemDaemon(_ path: String) -> Bool {
        let path = path.lowercased()
        return daemonPrefixes.contains(where: path.hasPrefix)
    }

    /// Everything the OS ships, daemons and command line tools alike. None of
    /// these is a dev server.
    static func isShippedWithSystem(_ path: String) -> Bool {
        let path = path.lowercased()
        return (daemonPrefixes + toolPrefixes).contains(where: path.hasPrefix)
    }

    /// `/usr/libexec` and `/system` only. `/bin/zsh -c` and `/usr/bin/env` are
    /// wrappers, so `ProcessRole` must not treat every system binary as a boundary.
    private static let daemonPrefixes = ["/system/", "/usr/libexec/"]
    private static let toolPrefixes = ["/usr/sbin/", "/usr/bin/", "/sbin/", "/bin/", "/library/apple/"]
}
