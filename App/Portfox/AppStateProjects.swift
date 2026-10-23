import Foundation
import PortfoxKit

/// The user's own project names. Applied in `applyFilters`, so every surface
/// reading `result` shows them without asking.
@MainActor
extension AppState {
    /// Banners announce services straight off the scan diff, which never passes
    /// through `result`, so they take the user's project names here.
    func named(_ service: RunningService) -> RunningService {
        service.renamingProject(projectNames.name(forProjectAt:))
    }

    func customName(of group: ProjectGroup) -> String? {
        projectNames.name(forProjectAt: group.project.root)
    }

    func rename(_ group: ProjectGroup, to name: String) {
        projectNames.set(name, forProjectAt: group.project.root)
        applyFilters()
    }
}
