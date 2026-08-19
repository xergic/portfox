import Foundation

/// What makes two runs of the same service the same service, to the user.
///
/// Not `RunningService.id`: that is pid-derived and dies with the process, so it
/// cannot be written to disk. This survives a restart of the process and of the
/// app, which is what an ignore list needs.
public struct IgnoreKey: Hashable, Codable, Sendable {
    public let port: Int
    /// The project's service directory, or the executable path when there is no
    /// project. Anchoring on the project keeps two Node projects that share both
    /// a binary and a port distinct, since every Vite and Next server resolves to
    /// the same `node`.
    public let anchor: String

    /// Standardised rather than symlink-resolved. Resolving touches the
    /// filesystem and can answer differently across launches, which is exactly
    /// what a stored key must not do.
    public init(port: Int, anchor: String) {
        self.port = port
        self.anchor = (anchor as NSString).standardizingPath
    }

    /// Nil when the process gave up neither a project, a path nor an argv, which
    /// leaves nothing durable to key on. Ignore is hidden for those.
    public init?(_ service: RunningService) {
        let anchor = service.project?.serviceDirectory.path
            ?? service.listenerProcess.resolvedExecutablePath
            ?? service.listenerProcess.executableName
        guard !anchor.isEmpty else { return nil }
        self.init(port: service.port, anchor: anchor)
    }

    /// Last path component, for a label that fits a preferences row.
    public var anchorName: String { (anchor as NSString).lastPathComponent }
}

/// One ignored service, carrying enough identity from the moment it was ignored
/// to list in Preferences while nothing is running on that port. The key alone
/// would render as a bare path.
public struct IgnoredService: Codable, Hashable, Sendable, Identifiable {
    public var id: IgnoreKey { key }

    public let key: IgnoreKey
    /// `RunningService.displayName` when it was ignored.
    public let name: String
    /// `RunningService.subtitle` when it was ignored, else the anchor's name.
    public let detail: String

    public var port: Int { key.port }

    public init(key: IgnoreKey, name: String, detail: String) {
        self.key = key
        self.name = name
        self.detail = detail
    }

    public init?(_ service: RunningService) {
        guard let key = IgnoreKey(service) else { return nil }
        self.init(key: key, name: service.displayName, detail: service.subtitle ?? key.anchorName)
    }
}
