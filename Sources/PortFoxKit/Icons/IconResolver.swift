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
        "app/icon.png", "app/icon.svg", "app/apple-icon.png", "app/favicon.ico",
        "src/app/icon.png", "src/app/favicon.ico",
        "public/favicon.svg", "public/favicon.png", "public/favicon.ico",
        "public/icon.png", "public/apple-touch-icon.png", "public/logo.png",
        "static/favicon.svg", "static/favicon.png", "static/favicon.ico",
        "assets/icon.png", "assets/favicon.png",
        "favicon.svg", "favicon.png", "favicon.ico"
    ]

    /// Vite and Nuxt ship these in every new project, so they identify the
    /// framework rather than the user's project and must not win.
    static let genericIconNames: Set<String> = ["vite.svg", "nuxt.svg", "next.svg", "vercel.svg", "svelte.svg"]

    public init() {}

    private var fileManager: FileManager { .default }

    public func resolve(project: ProjectSnapshot?, type: ServiceType) -> IconSource {
        if let project, let path = project.iconPath ?? projectIconPath(for: project) {
            return .projectFile(path: path)
        }
        return type == .unknown ? .symbol(type.fallbackSymbol) : .framework(type)
    }

    /// Absolute path of the best project icon, or nil.
    public func projectIconPath(for project: ProjectSnapshot) -> String? {
        // An Expo config names its icon explicitly, which beats guessing.
        if let declared = expoIconPath(for: project) { return declared }

        let directories = project.serviceDirectory == project.root
            ? [project.root]
            : [project.serviceDirectory, project.root]

        for directory in directories {
            for relative in Self.searchPaths {
                guard !Self.genericIconNames.contains((relative as NSString).lastPathComponent) else { continue }
                let candidate = directory.appendingPathComponent(relative)
                if fileManager.fileExists(atPath: candidate.path) { return candidate.path }
            }
        }
        return nil
    }

    private func expoIconPath(for project: ProjectSnapshot) -> String? {
        for directory in [project.serviceDirectory, project.root] {
            guard let declared = ManifestReader.expoConfig(in: directory)?.declaredIconPath else { continue }
            // Not `URL(fileURLWithPath:relativeTo:)`. Project URLs are not always
            // flagged as directories, and that initialiser then resolves
            // "./assets/icon.png" against the parent instead.
            let candidate = directory.appendingPathComponent(declared).standardizedFileURL
            if fileManager.fileExists(atPath: candidate.path) { return candidate.path }
        }
        return nil
    }
}
