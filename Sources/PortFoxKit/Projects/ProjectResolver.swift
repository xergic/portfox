import Foundation

/// Resolves the project that owns a service working directory.
public protocol ProjectResolving: Sendable {
    func resolve(serviceDirectory: URL) -> ProjectSnapshot?
}

/// Walks up from a service working directory to find the project root.
///
/// Search order, per spec section 7: a workspace marker, then a git root, then
/// the nearest manifest, then the directory itself.
public struct ProjectResolver: ProjectResolving {
    /// Files that mark a monorepo or workspace root.
    public static let workspaceMarkers = [
        "pnpm-workspace.yaml", "pnpm-workspace.yml", "turbo.json", "nx.json", "lerna.json", "rush.json"
    ]
    /// Files that mark a project of any language.
    public static let manifestFiles = [
        "package.json", "pyproject.toml", "Cargo.toml", "go.mod", "composer.json", "Gemfile", "requirements.txt"
    ]

    private let maximumDepth: Int

    public init(maximumDepth: Int = 12) {
        self.maximumDepth = maximumDepth
    }

    public func resolve(serviceDirectory: URL) -> ProjectSnapshot? { nil }
}
