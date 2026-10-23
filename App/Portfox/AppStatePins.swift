import Foundation
import PortfoxKit

/// What a list draws, pinned first. Shared by the popover and the dashboard so
/// the drawn order and the order the arrow keys walk can never disagree.
struct ListSections {
    var pinnedGroups: [ProjectGroup] = []
    var pinnedServices: [RunningService] = []
    /// Pins with nothing running, drawn as placeholder rows.
    var stoppedPins: [Pin] = []
    var rest: ScanResult

    /// The rows under the Pinned heading. Pinned projects lead the project
    /// headings instead, because a row drawn after a heading reads as part of it.
    var hasPinnedRows: Bool { !pinnedServices.isEmpty || !stoppedPins.isEmpty }

    var drawingOrder: [RunningService] {
        pinnedServices + pinnedGroups.flatMap(\.services) + rest.drawingOrder
    }

    var isEmpty: Bool {
        !hasPinnedRows && pinnedGroups.isEmpty && rest.services.isEmpty
    }
}

@MainActor
extension AppState {
    func isPinned(_ group: ProjectGroup) -> Bool { pins.contains(group) }
    func isPinned(_ service: RunningService) -> Bool { pins.contains(service) }

    /// Unpinning removes whichever pin the heading answers to, which for a
    /// sibling group need not be one rooted where the heading is now.
    func togglePin(_ group: ProjectGroup) {
        defer { applyFilters() }
        let current = pins.projectPins(for: group)
        guard current.isEmpty else { return pins.remove(current) }
        pins.toggle(Pin(
            target: .project(root: group.project.root.path),
            name: group.project.name,
            detail: nil,
            type: group.services.first?.type ?? .unknown,
            iconPath: projectIcons.iconPath(for: group)
        ))
    }

    func togglePin(_ service: RunningService) {
        guard let key = ServiceKey(service) else { return }
        defer { applyFilters() }
        pins.toggle(Pin(
            target: .service(key),
            name: service.displayName,
            detail: service.project?.name ?? service.subtitle,
            type: service.type,
            iconPath: nil
        ))
    }

    func unpin(_ pin: Pin) {
        pins.remove([pin])
        applyFilters()
    }

    /// A project pin reads the user's current name for it, which may have
    /// changed since it was pinned.
    func displayName(of pin: Pin) -> String {
        guard case .project(let root) = pin.target else { return pin.name }
        return projectNames.name(forProjectAt: URL(fileURLWithPath: root)) ?? pin.name
    }

    /// Pinned projects and services lifted out of `result`, so each draws once.
    /// A pinned service inside a pinned project stays in its project.
    func sections(of result: ScanResult, showsStoppedPins: Bool) -> ListSections {
        guard !pins.isEmpty else { return ListSections(rest: result) }

        let groups = result.groups.filter(pins.contains)
        let inPinnedGroups = Set(groups.flatMap(\.services).map(\.id))
        let services = result.services.filter { !inPinnedGroups.contains($0.id) && pins.contains($0) }
        let lifted = inPinnedGroups.union(services.map(\.id))
        return ListSections(
            pinnedGroups: groups,
            pinnedServices: services,
            stoppedPins: showsStoppedPins ? stoppedPins : [],
            rest: result.keeping { !lifted.contains($0.id) }
        )
    }
}
