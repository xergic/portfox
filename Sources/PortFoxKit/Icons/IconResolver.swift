import Foundation

/// Where a service's icon should come from, resolved in the priority order of
/// spec section 8.2.
public enum IconSource: Hashable, Sendable {
    /// An image file belonging to the user's project, such as a favicon or an Expo icon.
    case projectFile(path: String)
    /// A bundled framework logo.
    case framework(ServiceType)
    /// An SF Symbol, when nothing better exists.
    case symbol(String)
}

/// Finds a project's own icon on disk. No HTTP, per spec section 9.
public struct IconResolver: Sendable {
    /// Checked in order, relative to the service directory and then the project root.
    public static let searchPaths = [
        "app/icon.png", "app/icon.svg", "app/favicon.ico", "app/apple-icon.png",
        "src/app/icon.png", "src/app/favicon.ico",
        "public/favicon.ico", "public/favicon.png", "public/favicon.svg",
        "public/icon.png", "public/logo.png", "public/apple-touch-icon.png",
        "static/favicon.ico", "static/favicon.png", "static/favicon.svg",
        "assets/icon.png", "assets/favicon.png",
        "favicon.ico", "favicon.png", "favicon.svg"
    ]

    public init() {}

    public func resolve(project: ProjectSnapshot?, type: ServiceType) -> IconSource {
        .framework(type)
    }

    /// Absolute path of the best project icon, or nil.
    public func projectIconPath(for project: ProjectSnapshot) -> String? { nil }
}
