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

    public init() {}

    /// Every candidate image, best first.
    public func assets(in project: ProjectSnapshot) -> [ProjectAsset] {
        []
    }
}
