import Foundation

extension ScanResult {
    /// The same result with every project the user renamed carrying their name,
    /// keyed by project root. The headings are re-sorted, because they are sorted
    /// by the name that just changed.
    ///
    /// Returns `self` when no root has a custom name, which is the common case on
    /// every tick.
    public func renamingProjects(_ customName: (URL) -> String?) -> ScanResult {
        let renamesAny = groups.contains { customName($0.project.root) != nil }
            || everyService.contains { $0.project.map { customName($0.root) != nil } ?? false }
        guard renamesAny else { return self }

        func rename(_ service: RunningService) -> RunningService { service.renamingProject(customName) }
        let renamedGroups = groups.map { group in
            var project = group.project
            if let name = customName(project.root) { project.name = name }
            return ProjectGroup(project: project, services: group.services.map(rename))
        }
        return ScanResult(
            services: services.map(rename),
            groups: renamedGroups.sorted(by: ProjectGroup.byName),
            standalone: standalone.map(rename),
            agentTools: agentTools.map(rename),
            allSockets: allSockets,
            hidden: hidden.map(rename)
        )
    }
}

extension RunningService {
    /// For a service that never passes through a `ScanResult` the user sees, such
    /// as the one a banner announces.
    public func renamingProject(_ customName: (URL) -> String?) -> RunningService {
        guard let root = project?.root, let name = customName(root) else { return self }
        var renamed = self
        renamed.project?.name = name
        return renamed
    }
}
