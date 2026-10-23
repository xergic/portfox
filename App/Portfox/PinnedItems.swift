import Foundation
import Observation
import PortfoxKit

/// A project or a single service the user keeps at the top of both lists.
struct Pin: Codable, Hashable, Identifiable {
    enum Target: Codable, Hashable {
        case project(root: String)
        case service(ServiceKey)
    }

    let target: Target
    /// Captured when pinned, because a stopped pin has no service left to read
    /// them from and still has to draw its row.
    let name: String
    let detail: String?
    let type: ServiceType
    let iconPath: String?

    var id: Target { target }

    var port: Int? {
        guard case .service(let key) = target else { return nil }
        return key.port
    }
}

/// Pins, keyed like the ignore and watch lists so they survive a restart of
/// the server and of the app.
@MainActor
@Observable
final class PinnedItems {
    private static let defaultsKey = "pinnedItems"

    private(set) var pins: [Pin] {
        didSet { reindex() }
    }
    /// Every row asks on every redraw, and building a `ServiceKey` standardises
    /// a path, so the ports are checked first.
    @ObservationIgnored private var targets: Set<Pin.Target> = []
    @ObservationIgnored private var servicePorts: Set<Int> = []
    @ObservationIgnored private var projectRoots: [String] = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.defaultsKey)
        pins = stored.flatMap { try? JSONDecoder().decode([Pin].self, from: $0) } ?? []
        reindex()
    }

    var isEmpty: Bool { pins.isEmpty }

    func contains(_ group: ProjectGroup) -> Bool {
        !projectPins(for: group).isEmpty
    }

    func contains(_ service: RunningService) -> Bool {
        guard servicePorts.contains(service.port), let key = ServiceKey(service) else { return false }
        return targets.contains(.service(key))
    }

    /// The project pins a heading answers to. Not only its own root: a sibling
    /// group's heading moves between the shared parent and a single repository
    /// as its members start and stop, and the pin has to follow it.
    func projectPins(for group: ProjectGroup) -> [Pin] {
        guard !projectRoots.isEmpty else { return [] }
        let groupRoot = group.project.root.path
        let roots = projectRoots.filter { root in
            groupRoot == root || groupRoot.hasPrefix(root + "/") || group.services.contains { $0.isInProject(at: root) }
        }
        return pins.filter { pin in
            guard case .project(let root) = pin.target else { return false }
            return roots.contains(root)
        }
    }

    func toggle(_ pin: Pin) {
        if targets.contains(pin.target) {
            remove([pin])
        } else {
            pins.append(pin)
            save()
        }
    }

    func remove(_ removed: [Pin]) {
        let gone = Set(removed.map(\.target))
        pins.removeAll { gone.contains($0.target) }
        save()
    }

    /// Pins with nothing running in `scan`.
    func stopped(in scan: ScanResult) -> [Pin] {
        guard !pins.isEmpty else { return [] }
        let running = scan.everyService
        return pins.filter { pin in
            switch pin.target {
            case .project(let root):
                return !running.contains { $0.isInProject(at: root) }
            case .service(let key):
                return !running.contains { $0.port == key.port && ServiceKey($0) == key }
            }
        }
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(pins), forKey: Self.defaultsKey)
    }

    private func reindex() {
        targets = Set(pins.map(\.target))
        servicePorts = []
        projectRoots = []
        for target in targets {
            switch target {
            case .project(let root): projectRoots.append(root)
            case .service(let key): servicePorts.insert(key.port)
            }
        }
    }
}
