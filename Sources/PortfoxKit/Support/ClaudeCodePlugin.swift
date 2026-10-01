import Foundation

/// Where a process's command line says it came from inside Claude Code's plugin
/// cache, `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/...`.
///
/// Only the cache layout is read. The `marketplaces/` checkout holds the plugin
/// source without a version directory, so it names neither the plugin nor the
/// version reliably.
struct ClaudeCodePlugin: Equatable {
    let name: String
    let version: String

    private static let marker = "/.claude/plugins/cache/"

    /// Marketplace, plugin and version must all be followed by a further `/`,
    /// so a bare `.../cache/foo` or a `.claude` directory elsewhere never matches.
    init?(command: String) {
        guard let markerRange = command.range(of: Self.marker) else { return nil }

        let segments = command[markerRange.upperBound...].split(separator: "/", omittingEmptySubsequences: false)
        guard segments.count > 3 else { return nil }
        let (marketplace, name, version) = (segments[0], segments[1], segments[2])
        guard ![marketplace, name, version].contains(where: { $0.isEmpty || $0.contains(" ") }) else { return nil }

        self.name = String(name)
        self.version = String(version)
    }
}
