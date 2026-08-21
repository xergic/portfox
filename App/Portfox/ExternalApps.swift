import AppKit
import Foundation

struct ExternalApp: Identifiable, Hashable, Sendable {
    let bundleID: String
    let name: String
    /// Whether handing this app an executable script makes it run the script in a
    /// visible window. Only set on terminals that were tested doing it.
    var runsHandedOverScript = false

    var id: String { bundleID }
}

/// Editors and terminals installed on this machine, and how to point one at a
/// directory.
///
/// A bundle identifier that is not installed simply resolves to nil and never
/// appears, so an entry that is wrong costs a missing menu item rather than a
/// broken one.
@MainActor
enum ExternalApps {
    /// Ranked by what a developer most likely reaches for. The first installed
    /// one becomes the default.
    ///
    /// Verified installed and launching on the development machine: VS Code, Zed,
    /// Xcode, Android Studio, T3 Code. The rest are published identifiers that
    /// could not be tested here.
    static let editorCandidates: [ExternalApp] = [
        ExternalApp(bundleID: "com.todesktop.230313mzl4w4u92", name: "Cursor"),
        ExternalApp(bundleID: "com.exafunction.windsurf", name: "Windsurf"),
        ExternalApp(bundleID: "com.t3tools.t3code", name: "T3 Code"),
        ExternalApp(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code"),
        ExternalApp(bundleID: "com.microsoft.VSCodeInsiders", name: "VS Code Insiders"),
        ExternalApp(bundleID: "dev.zed.Zed", name: "Zed"),
        ExternalApp(bundleID: "com.sublimetext.4", name: "Sublime Text"),
        ExternalApp(bundleID: "com.jetbrains.WebStorm", name: "WebStorm"),
        ExternalApp(bundleID: "com.jetbrains.intellij", name: "IntelliJ IDEA"),
        ExternalApp(bundleID: "com.jetbrains.pycharm", name: "PyCharm"),
        ExternalApp(bundleID: "com.jetbrains.PhpStorm", name: "PhpStorm"),
        ExternalApp(bundleID: "com.jetbrains.rubymine", name: "RubyMine"),
        ExternalApp(bundleID: "com.jetbrains.goland", name: "GoLand"),
        ExternalApp(bundleID: "com.apple.dt.Xcode", name: "Xcode"),
        ExternalApp(bundleID: "com.google.android.studio", name: "Android Studio")
    ]

    /// `runsHandedOverScript` was established by handing each app a `.command`
    /// file and checking that its body ran. Terminal, iTerm2 and Warp all did.
    /// The others open at a directory but were never tested with a script, so
    /// Restart declines rather than guessing, and offers Copy Command instead.
    static let terminalCandidates: [ExternalApp] = [
        ExternalApp(bundleID: "com.googlecode.iterm2", name: "iTerm", runsHandedOverScript: true),
        ExternalApp(bundleID: "dev.warp.Warp-Stable", name: "Warp", runsHandedOverScript: true),
        ExternalApp(bundleID: "com.mitchellh.ghostty", name: "Ghostty"),
        ExternalApp(bundleID: "com.github.wez.wezterm", name: "WezTerm"),
        ExternalApp(bundleID: "org.alacritty", name: "Alacritty"),
        ExternalApp(bundleID: "net.kovidgoyal.kitty", name: "kitty"),
        ExternalApp(bundleID: "com.apple.Terminal", name: "Terminal", runsHandedOverScript: true)
    ]

    /// Resolved once. LaunchServices is cheap but this is read from view bodies,
    /// and an app installed while Portfox runs is not worth a lookup per redraw.
    static let editors: [ExternalApp] = installed(among: editorCandidates)
    static let terminals: [ExternalApp] = installed(among: terminalCandidates)

    static func editor(id: String?) -> ExternalApp? { resolve(id, among: editors) }
    static func terminal(id: String?) -> ExternalApp? { resolve(id, among: terminals) }

    private static func url(of app: ExternalApp) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID)
    }

    /// Opens the given files with the app. A directory handed to an editor opens
    /// as a project, and handed to a terminal opens a window already in it.
    static func open(_ urls: [URL], with app: ExternalApp) async throws {
        guard let application = url(of: app) else {
            throw ExternalAppError.notInstalled(app.name)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.open(urls, withApplicationAt: application, configuration: configuration)
    }

    /// The stored choice when it is still installed, otherwise the highest ranked
    /// one that is. A preference naming an app the user has since deleted must not
    /// take the menu item away.
    static func resolve(_ id: String?, among apps: [ExternalApp]) -> ExternalApp? {
        if let id, let chosen = apps.first(where: { $0.bundleID == id }) { return chosen }
        return apps.first
    }

    private static func installed(among candidates: [ExternalApp]) -> [ExternalApp] {
        candidates.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
    }
}

enum ExternalAppError: LocalizedError {
    case notInstalled(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled(let name): "\(name) is not installed."
        }
    }
}
