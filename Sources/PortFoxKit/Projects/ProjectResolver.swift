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
    private static let genericNames: Set<String> = ["api", "web", "app", "server", "client", "src"]

    private let maximumDepth: Int

    public init(maximumDepth: Int = 12) {
        self.maximumDepth = maximumDepth
    }

    public func resolve(serviceDirectory rawDirectory: URL) -> ProjectSnapshot? {
        guard FileManager.default.fileExists(atPath: rawDirectory.path) else { return nil }

        let directory = rawDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.resolvingSymlinksInPath()

        let chain = ancestorChain(from: directory, home: home)
        let entries = Dictionary(uniqueKeysWithValues: chain.map { ($0, Self.directoryEntries(at: $0)) })

        let workspaceRoot = chain.reversed().first { isWorkspaceRoot($0, entries: entries) }
        let gitRoot = chain.reversed().first { (entries[$0] ?? []).contains(".git") }
        let manifestRoot = chain.first { dir in (entries[dir] ?? []).contains { Self.manifestFiles.contains($0) } }

        let root: URL
        let rootKind: ProjectSnapshot.RootKind
        if let workspaceRoot {
            root = workspaceRoot
            rootKind = .workspace
        } else if let gitRoot {
            root = gitRoot
            rootKind = .git
        } else if let manifestRoot {
            root = manifestRoot
            rootKind = .manifest
        } else {
            root = directory
            rootKind = .directory
        }

        let serviceManifest = ManifestReader.read(in: directory)
        let rootManifest = root.path == directory.path ? serviceManifest : ManifestReader.read(in: root)
        let combinedManifest = serviceManifest.merging(parent: rootManifest)

        return ProjectSnapshot(
            root: root,
            serviceDirectory: directory,
            name: resolvedName(serviceManifest: serviceManifest, rootManifest: rootManifest, root: root),
            subpath: subpath(of: directory, relativeTo: root),
            files: entries[directory] ?? Self.directoryEntries(at: directory),
            rootFiles: entries[root] ?? Self.directoryEntries(at: root),
            dependencies: combinedManifest.dependencies,
            scripts: combinedManifest.scripts,
            rootKind: rootKind,
            iconPath: nil
        )
    }

    // MARK: - Tree walk

    /// Visible to tests so the home/root stop conditions can be checked without
    /// touching the filesystem.
    func ancestorChain(from start: URL, home: URL) -> [URL] {
        var chain: [URL] = []
        var current = start
        for _ in 0..<maximumDepth {
            chain.append(current)
            if current.path == home.path || current.path == "/" { break }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return chain
    }

    private static func directoryEntries(at directory: URL) -> Set<String> {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        return Set(names)
    }

    private func isWorkspaceRoot(_ directory: URL, entries: [URL: Set<String>]) -> Bool {
        let names = entries[directory] ?? []
        if names.contains(where: Self.workspaceMarkers.contains) { return true }
        guard names.contains("package.json") else { return false }
        return ManifestReader.packageJSON(in: directory)?.declaresWorkspaces == true
    }

    // MARK: - Snapshot fields

    private func subpath(of directory: URL, relativeTo root: URL) -> String? {
        guard directory.path != root.path else { return nil }
        return directory.pathComponents.dropFirst(root.pathComponents.count).joined(separator: "/")
    }

    private func resolvedName(serviceManifest: ManifestData, rootManifest: ManifestData, root: URL) -> String {
        var name = Self.displayName(serviceManifest.name ?? rootManifest.name ?? root.lastPathComponent)
        if Self.genericNames.contains(name.lowercased()), let rootRawName = rootManifest.name {
            name = Self.displayName(rootRawName)
        }
        return name
    }

    private static func displayName(_ rawName: String) -> String {
        guard rawName.hasPrefix("@"), let slashIndex = rawName.firstIndex(of: "/") else { return rawName }
        return String(rawName[rawName.index(after: slashIndex)...])
    }
}
