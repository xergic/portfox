import Foundation
import Observation
import PortFoxKit

/// State that belongs to the dashboard alone. Kept out of `AppState` so the
/// popover carries none of it and so closing the window can discard it.
@MainActor
@Observable
final class DashboardState {
    enum Tab: String, CaseIterable {
        case services
        case processTree

        var displayName: String {
            switch self {
            case .services: "Services"
            case .processTree: "Process Tree"
            }
        }
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all
        case web
        case api
        case database
        case system

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .all: "All"
            case .web: "Web"
            case .api: "API"
            case .database: "DB"
            case .system: "System"
            }
        }

        func accepts(_ service: RunningService) -> Bool {
            switch self {
            case .all: true
            case .web: service.type.category == .web
            case .api: service.type.category == .api || service.type.category == .tooling
            case .database: service.type.category == .database || service.type.category == .infrastructure
            case .system: service.classification == .systemNoise
            }
        }
    }

    var tab: Tab = .services
    var filter: Filter = .all
    var search = ""
    var selectedServiceID: String?

    enum ProbeOutcome {
        case success(HTTPProbeResult)
        case failure(String)
    }

    private(set) var probes: [String: ProbeOutcome] = [:]
    private(set) var probingServiceIDs: Set<String> = []

    private let probe = HTTPProbe()

    func selection(in result: ScanResult) -> RunningService? {
        let visible = services(in: result)
        if let selectedServiceID, let match = visible.first(where: { $0.id == selectedServiceID }) {
            return match
        }
        return visible.first
    }

    /// Everything the sidebar shows, after the chip and the search box.
    func services(in result: ScanResult) -> [RunningService] {
        result.services
            .filter { filter.accepts($0) }
            .filter { matches(search, $0) }
    }

    func groups(in result: ScanResult) -> [ProjectGroup] {
        let allowed = Set(services(in: result).map(\.id))
        return result.groups
            .map { ProjectGroup(project: $0.project, services: $0.services.filter { allowed.contains($0.id) }) }
            .filter { !$0.services.isEmpty }
    }

    func standalone(in result: ScanResult) -> [RunningService] {
        let allowed = Set(services(in: result).map(\.id))
        return result.standalone.filter { allowed.contains($0.id) }
    }

    private func matches(_ query: String, _ service: RunningService) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return true }

        let haystack = [
            String(service.port),
            service.displayName,
            service.project?.name,
            service.subtitle,
            service.listenerProcess.executableName
        ]
        return haystack.compactMap { $0?.lowercased() }.contains { $0.contains(needle) }
    }

    // MARK: - HTTP probe

    func probeResult(for service: RunningService) -> ProbeOutcome? {
        probes[service.id]
    }

    func isProbing(_ service: RunningService) -> Bool {
        probingServiceIDs.contains(service.id)
    }

    /// Runs only when asked. Nothing probes on the refresh tick, so an open
    /// dashboard never hits the user's dev servers in the background.
    func runProbe(for service: RunningService) async {
        guard let url = service.localURL, !probingServiceIDs.contains(service.id) else { return }

        probingServiceIDs.insert(service.id)
        defer { probingServiceIDs.remove(service.id) }

        do {
            probes[service.id] = .success(try await probe.probe(url))
        } catch {
            probes[service.id] = .failure(error.localizedDescription)
        }
    }

    /// A restarted service keeps its port but gets a new identity, so its old
    /// response would otherwise be shown against a process that never sent it.
    func forgetProbes(missingFrom result: ScanResult) {
        let live = Set(result.services.map(\.id))
        probes = probes.filter { live.contains($0.key) }
    }
}
