import Foundation
import Observation
import PortFoxKit

/// State that belongs to the dashboard alone. Kept out of `AppState` so the
/// popover carries none of it and so closing the window can discard it.
@MainActor
@Observable
final class DashboardState {
    enum Filter: String, CaseIterable, Identifiable {
        case all
        case web
        case api
        case database
        case system
        case ignored

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .all: "All"
            case .web: "Web"
            case .api: "API"
            case .database: "DB"
            case .system: "System"
            case .ignored: "Ignored"
            }
        }

        func accepts(_ service: RunningService) -> Bool {
            switch self {
            case .all: true
            case .web: service.type.category == .web
            case .api: service.type.category == .api || service.type.category == .tooling
            case .database: service.type.category == .database || service.type.category == .infrastructure
            case .system: service.classification == .systemNoise
            // Not a predicate. The Ignored chip swaps the whole result the pane
            // renders for `AppState.ignoredResult`, so everything reaching here
            // is already ignored and only the search box still applies.
            case .ignored: true
            }
        }
    }

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
        selection(among: services(in: result))
    }

    /// For callers that have already narrowed the result and must not pay for a
    /// second pass to find out what is selected.
    func selection(among services: [RunningService]) -> RunningService? {
        if let selectedServiceID, let match = services.first(where: { $0.id == selectedServiceID }) {
            return match
        }
        return services.first
    }

    /// The result narrowed by the chip and the search box, with its project
    /// headings rebuilt so none of them names a service the filter dropped.
    func filtered(_ result: ScanResult) -> ScanResult {
        // Normalised once per pass, not once per service.
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        return result.keeping { filter.accepts($0) && matches(needle, $0) }
    }

    /// Everything the sidebar shows, after the chip and the search box.
    func services(in result: ScanResult) -> [RunningService] { filtered(result).services }

    func groups(in result: ScanResult) -> [ProjectGroup] { filtered(result).groups }

    func standalone(in result: ScanResult) -> [RunningService] { filtered(result).standalone }

    /// `needle` is already trimmed and lowercased by `filtered`.
    private func matches(_ needle: String, _ service: RunningService) -> Bool {
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
