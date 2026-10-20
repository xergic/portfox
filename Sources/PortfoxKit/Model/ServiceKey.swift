import Foundation

/// What makes two runs of the same service the same service, to the user.
///
/// Not `RunningService.id`: that is pid-derived and dies with the process, so it
/// cannot be written to disk. This survives a restart of the process and of the
/// app, which is what the ignore and watch lists need.
public struct ServiceKey: Hashable, Codable, Sendable {
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
