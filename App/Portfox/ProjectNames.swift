import Foundation

/// Names the user gave projects by hand, keyed by project root path.
///
/// A preference, not a fact about the machine, so it lives in the app beside
/// `ProjectIconOverrides` and reaches the kit only through `renamingProjects`.
@MainActor
final class ProjectNames {
    private static let defaultsKey = "projectNames"

    private var names: [String: String]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        names = defaults.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
        prune()
    }

    func name(forProjectAt root: URL) -> String? {
        names[root.path]
    }

    /// A blank name clears the entry, so the detected name comes back.
    func set(_ name: String, forProjectAt root: URL) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        names[root.path] = trimmed.isEmpty ? nil : trimmed
        defaults.set(names, forKey: Self.defaultsKey)
    }

    /// A project folder that was deleted or moved can never match again.
    private func prune() {
        let live = names.filter { FileManager.default.fileExists(atPath: $0.key) }
        guard live.count != names.count else { return }
        names = live
        defaults.set(names, forKey: Self.defaultsKey)
    }
}
