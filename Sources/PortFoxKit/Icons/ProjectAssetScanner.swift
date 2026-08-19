import Foundation

/// An image inside a project that could serve as its icon.
public struct ProjectAsset: Identifiable, Hashable, Sendable {
    public var id: String { path }

    public let path: String
    /// Path relative to the project root, for display.
    public let relativePath: String
    public let byteSize: Int

    public init(path: String, relativePath: String, byteSize: Int) {
        self.path = path
        self.relativePath = relativePath
        self.byteSize = byteSize
    }

    public var filename: String { (path as NSString).lastPathComponent }
}

/// Finds images a user could pick as their project's icon.
///
/// Deliberately shallow and bounded. This runs when a menu is opened, so it must
/// never walk a `node_modules` tree or a build output directory.
public struct ProjectAssetScanner: Sendable {
    /// Directories searched relative to the project root, in order.
    public static let searchDirectories = [
        "", "public", "app", "src/app", "static", "assets", "src/assets",
        "public/images", "public/img", "resources", "images", "img", "icons", "public/icons"
    ]

    public static let imageExtensions: Set<String> = ["png", "svg", "ico", "jpg", "jpeg", "icns", "webp", "gif"]

    /// Hard cap so a menu never takes a noticeable time to open.
    public static let maximumResults = 60

    private static let maximumFileSizeInBytes = 4 * 1024 * 1024

    private static let excludedDirectoryNames: Set<String> = [
        "node_modules", ".git", "dist", "build", ".next", ".nuxt", ".output",
        ".svelte-kit", "vendor", "target", "Pods", ".venv", "__pycache__", ".cache", "coverage"
    ]

    /// Name stems that read as an icon or logo, checked against a file's name
    /// without its extension.
    private static let iconNameStems: Set<String> = [
        "icon", "logo", "favicon", "apple-touch-icon", "app-icon", "mark", "brand"
    ]

    /// svg first because it scales cleanly into a menu-bar icon, icns last
    /// because it is the least likely to be a plain image a picker can preview.
    private static let extensionRanks: [String: Int] = ["svg": 0, "png": 1, "ico": 2, "icns": 3]

    private struct Candidate {
        let asset: ProjectAsset
        let tier: Int
        let searchPathIndex: Int
        let extensionRank: Int
        let isInServiceDirectory: Bool
    }

    public init() {}

    private var fileManager: FileManager { .default }

    /// Every candidate image, best first.
    public func assets(in project: ProjectSnapshot) -> [ProjectAsset] {
        let anchors = project.serviceDirectory == project.root
            ? [project.root]
            : [project.serviceDirectory, project.root]

        var seenResolvedPaths = Set<String>()
        var candidates: [Candidate] = []

        collectLoop: for anchor in anchors {
            guard !Self.excludedDirectoryNames.contains(anchor.lastPathComponent) else { continue }

            for subdirectory in Self.searchDirectories {
                guard !isExcluded(subdirectory: subdirectory) else { continue }
                let directory = subdirectory.isEmpty ? anchor : anchor.appendingPathComponent(subdirectory)

                guard let entries = try? fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }

                for entry in entries {
                    guard Self.imageExtensions.contains(entry.pathExtension.lowercased()) else { continue }

                    // realpath, not the enumerated path, so a symlink into an
                    // already-scanned directory can't be counted twice.
                    let resolvedPath = entry.resolvingSymlinksInPath().path
                    guard seenResolvedPaths.insert(resolvedPath).inserted else { continue }

                    guard let candidate = candidate(
                        for: entry,
                        resolvedPath: resolvedPath,
                        subdirectory: subdirectory,
                        anchor: anchor,
                        project: project
                    ) else { continue }

                    candidates.append(candidate)
                    // The remaining search directories cannot lower the count,
                    // only lengthen the scan, so stop as soon as the cap is hit.
                    if candidates.count >= Self.maximumResults { break collectLoop }
                }
            }
        }

        return candidates
            .sorted(by: isOrderedBefore)
            .map(\.asset)
    }

    private func isExcluded(subdirectory: String) -> Bool {
        subdirectory.split(separator: "/").contains { Self.excludedDirectoryNames.contains(String($0)) }
    }

    private func candidate(
        for entry: URL,
        resolvedPath: String,
        subdirectory: String,
        anchor: URL,
        project: ProjectSnapshot
    ) -> Candidate? {
        guard let values = try? entry.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true,
              let size = values.fileSize,
              size > 0,
              size <= Self.maximumFileSizeInBytes
        else { return nil }

        let filename = entry.lastPathComponent
        let searchPathRelative = subdirectory.isEmpty ? filename : "\(subdirectory)/\(filename)"
        let (tier, searchPathIndex) = rank(filename: filename, searchPathRelative: searchPathRelative)

        let asset = ProjectAsset(
            path: entry.path,
            relativePath: relativePath(for: entry, project: project),
            byteSize: size
        )

        return Candidate(
            asset: asset,
            tier: tier,
            searchPathIndex: searchPathIndex,
            extensionRank: Self.extensionRanks[entry.pathExtension.lowercased()] ?? 4,
            isInServiceDirectory: anchor == project.serviceDirectory
        )
    }

    /// Tier 1 wins on the index it was found at in `IconResolver.searchPaths`,
    /// so ties only need `searchPathIndex` when two directories both produce a
    /// match at the same array position.
    private func rank(filename: String, searchPathRelative: String) -> (tier: Int, searchPathIndex: Int) {
        guard !IconResolver.genericIconNames.contains(filename) else { return (3, .max) }

        if let index = IconResolver.searchPaths.firstIndex(where: {
            $0.compare(searchPathRelative, options: .caseInsensitive) == .orderedSame
        }) {
            return (1, index)
        }

        let stem = (filename as NSString).deletingPathExtension.lowercased()
        if Self.iconNameStems.contains(stem) { return (2, .max) }

        return (3, .max)
    }

    private func isOrderedBefore(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
        if lhs.searchPathIndex != rhs.searchPathIndex { return lhs.searchPathIndex < rhs.searchPathIndex }
        if lhs.extensionRank != rhs.extensionRank { return lhs.extensionRank < rhs.extensionRank }
        if lhs.isInServiceDirectory != rhs.isInServiceDirectory { return lhs.isInServiceDirectory }
        return lhs.asset.relativePath.lowercased() < rhs.asset.relativePath.lowercased()
    }

    private func relativePath(for entry: URL, project: ProjectSnapshot) -> String {
        relative(entry, to: project.root) ?? relative(entry, to: project.serviceDirectory) ?? entry.lastPathComponent
    }

    private func relative(_ entry: URL, to base: URL) -> String? {
        let entryPath = entry.standardizedFileURL.path
        let basePath = base.standardizedFileURL.path
        guard entryPath.hasPrefix(basePath + "/") else { return nil }
        return String(entryPath.dropFirst(basePath.count + 1))
    }
}
