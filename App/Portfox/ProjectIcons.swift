import Foundation
import PortfoxKit

/// Which image stands for a project, and which images the user could choose from.
///
/// Split out of `AppState` because it shares nothing with the scan: it reads the
/// override store and the project's own files, and no refresh tick touches it.
@MainActor
final class ProjectIcons {
    private let overrides = ProjectIconOverrides()
    private let assetScanner = ProjectAssetScanner()

    /// The user's chosen icon, or whatever the resolver found on disk.
    func iconPath(for group: ProjectGroup) -> String? {
        overrides.iconPath(forProjectAt: group.project.root) ?? group.project.iconPath
    }

    func hasIconOverride(for group: ProjectGroup) -> Bool {
        overrides.hasOverride(forProjectAt: group.project.root)
    }

    func setIcon(_ path: String?, for group: ProjectGroup) {
        overrides.set(path, forProjectAt: group.project.root)
    }

    /// Images the user could pick. A sibling group has no manifests of its own,
    /// so every member project is scanned and the results merged.
    func projectAssets(for group: ProjectGroup) -> [ProjectAsset] {
        var seen: Set<String> = []
        var found: [ProjectAsset] = []

        for snapshot in group.services.compactMap(\.project) {
            for asset in assetScanner.assets(in: snapshot) where seen.insert(asset.path).inserted {
                found.append(asset)
            }
        }
        return found
    }
}
