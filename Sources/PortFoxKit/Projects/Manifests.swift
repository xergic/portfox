import Foundation

/// Facts read out of one project manifest file.
public struct ManifestData: Hashable, Sendable {
    public var name: String?
    /// Lowercased union of dependencies, devDependencies and peerDependencies.
    public var dependencies: Set<String>
    public var scripts: [String: String]
    /// True when a root package.json declares a `workspaces` field.
    public var declaresWorkspaces: Bool
    /// Path of a project icon declared by the manifest, relative to the manifest directory.
    public var declaredIconPath: String?

    public init(
        name: String? = nil,
        dependencies: Set<String> = [],
        scripts: [String: String] = [:],
        declaresWorkspaces: Bool = false,
        declaredIconPath: String? = nil
    ) {
        self.name = name
        self.dependencies = dependencies
        self.scripts = scripts
        self.declaresWorkspaces = declaresWorkspaces
        self.declaredIconPath = declaredIconPath
    }

    public static let empty = ManifestData()

    public var isEmpty: Bool {
        name == nil && dependencies.isEmpty && scripts.isEmpty && !declaresWorkspaces && declaredIconPath == nil
    }

    /// Combines a nearer manifest with one further up the tree. Nearer wins on
    /// scalar fields, collections merge.
    public func merging(parent: ManifestData) -> ManifestData {
        ManifestData(
            name: name ?? parent.name,
            dependencies: dependencies.union(parent.dependencies),
            scripts: scripts.merging(parent.scripts) { near, _ in near },
            declaresWorkspaces: declaresWorkspaces || parent.declaresWorkspaces,
            declaredIconPath: declaredIconPath ?? parent.declaredIconPath
        )
    }
}

/// Parses project manifests without executing anything. Dynamic JavaScript and
/// TypeScript configs are deliberately not evaluated, per spec section 9.
public enum ManifestReader {
    /// Reads `package.json` from `directory`.
    public static func packageJSON(in directory: URL) -> ManifestData? { nil }

    /// Reads Expo config from `app.json` or `app.config.json` in `directory`.
    /// `app.config.js` and `app.config.ts` are not evaluated.
    public static func expoConfig(in directory: URL) -> ManifestData? { nil }

    /// Reads `pyproject.toml` well enough to get the project name and its
    /// dependency names. Not a general TOML parser.
    public static func pyproject(in directory: URL) -> ManifestData? { nil }

    /// Reads dependency names out of `requirements.txt`.
    public static func requirementsTxt(in directory: URL) -> ManifestData? { nil }

    /// Every manifest recognised in `directory`, merged.
    public static func read(in directory: URL) -> ManifestData { .empty }
}
