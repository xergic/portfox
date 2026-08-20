import Foundation

/// What a project root looked like on disk when it was resolved. This is the
/// only project information detectors are allowed to read, which keeps them
/// pure and makes them trivial to test against a temp directory.
public struct ProjectSnapshot: Hashable, Codable, Sendable {
    /// Resolved project root, workspace root or git root.
    public let root: URL
    /// The process working directory, which may sit below `root` in a monorepo.
    public let serviceDirectory: URL
    /// Display name, resolved by `ProjectResolver`.
    public let name: String
    /// The project's own version, from its manifest.
    public let version: String?
    /// `serviceDirectory` relative to `root`, nil when they are the same.
    public let subpath: String?
    /// File and directory names directly inside `serviceDirectory`.
    public let files: Set<String>
    /// File and directory names directly inside `root`. Equal to `files` when not a monorepo.
    public let rootFiles: Set<String>
    /// Union of dependencies, devDependencies and peerDependencies from every
    /// manifest found, lowercased.
    public let dependencies: Set<String>
    /// npm scripts from the nearest package.json.
    public let scripts: [String: String]
    /// How the root was found.
    public let rootKind: RootKind
    /// Absolute path of an icon file belonging to the project, when one was found.
    public let iconPath: String?

    public enum RootKind: String, Codable, Sendable {
        case workspace
        case git
        case manifest
        case directory
    }

    public init(
        root: URL,
        serviceDirectory: URL,
        name: String,
        version: String? = nil,
        subpath: String? = nil,
        files: Set<String> = [],
        rootFiles: Set<String> = [],
        dependencies: Set<String> = [],
        scripts: [String: String] = [:],
        rootKind: RootKind = .directory,
        iconPath: String? = nil
    ) {
        self.root = root
        self.serviceDirectory = serviceDirectory
        self.name = name
        self.version = version
        self.subpath = subpath
        self.files = files
        self.rootFiles = rootFiles
        self.dependencies = dependencies
        self.scripts = scripts
        self.rootKind = rootKind
        self.iconPath = iconPath
    }

    /// True when any file in the service directory or the project root starts with `prefix`.
    public func hasFile(prefix: String) -> Bool {
        let needle = prefix.lowercased()
        return files.contains { $0.lowercased().hasPrefix(needle) }
            || rootFiles.contains { $0.lowercased().hasPrefix(needle) }
    }

    public func hasDependency(_ name: String) -> Bool {
        dependencies.contains(name.lowercased())
    }

    /// True for a Remix or React Router framework app, as opposed to a plain
    /// Vite app that merely uses react-router for client side routing. The
    /// framework packages run their own Vite dev server.
    public var isRemixFramework: Bool {
        hasDependency("@remix-run/dev") || hasDependency("@react-router/dev")
            || hasFile(prefix: "remix.config") || hasFile(prefix: "react-router.config")
    }

    /// Icons are resolved after the project itself, so the snapshot is rebuilt
    /// with the result rather than resolved twice.
    public func withIcon(path: String?) -> ProjectSnapshot {
        ProjectSnapshot(
            root: root,
            serviceDirectory: serviceDirectory,
            name: name,
            version: version,
            subpath: subpath,
            files: files,
            rootFiles: rootFiles,
            dependencies: dependencies,
            scripts: scripts,
            rootKind: rootKind,
            iconPath: path ?? iconPath
        )
    }
}

/// A project as shown in the UI. Several services can point at the same project.
public struct Project: Identifiable, Hashable, Sendable {
    public var id: String { root.path }

    public let root: URL
    public let name: String
    public let version: String?
    public let iconPath: String?
    /// Set when sibling repositories were folded under a shared parent directory.
    public let isSiblingGroup: Bool

    public init(
        root: URL,
        name: String,
        version: String? = nil,
        iconPath: String? = nil,
        isSiblingGroup: Bool = false
    ) {
        self.root = root
        self.name = name
        self.version = version
        self.iconPath = iconPath
        self.isSiblingGroup = isSiblingGroup
    }

    /// Home-relative path for display, for example `~/Projects/raqt`.
    public var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = root.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
