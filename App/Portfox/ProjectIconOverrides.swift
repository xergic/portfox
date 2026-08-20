import Foundation
import Observation

/// Icons the user has chosen by hand, keyed by project root path.
///
/// Kept in the app rather than in the kit because it is a preference, not a fact
/// about the machine. `IconResolver` stays a pure function of what is on disk.
@MainActor
@Observable
final class ProjectIconOverrides {
    private static let defaultsKey = "projectIconOverrides"

    private var paths: [String: String]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        paths = defaults.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
        prune()
    }

    func iconPath(forProjectAt root: URL) -> String? {
        paths[root.path]
    }

    func set(_ path: String?, forProjectAt root: URL) {
        if let path {
            paths[root.path] = path
        } else {
            paths.removeValue(forKey: root.path)
        }
        defaults.set(paths, forKey: Self.defaultsKey)
    }

    func hasOverride(forProjectAt root: URL) -> Bool {
        paths[root.path] != nil
    }

    /// A chosen icon can be deleted, renamed or moved by the user's own tooling.
    /// Dropping dead entries at launch stops a stale path from silently
    /// suppressing the icon that would otherwise be resolved.
    private func prune() {
        let live = paths.filter { FileManager.default.fileExists(atPath: $0.value) }
        guard live.count != paths.count else { return }
        paths = live
        defaults.set(paths, forKey: Self.defaultsKey)
    }
}
