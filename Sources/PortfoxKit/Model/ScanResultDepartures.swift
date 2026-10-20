import Foundation

extension ScanResult {
    /// Watched services in `previous` that are no longer listening, one per key.
    ///
    /// Keyed, not an id diff. A restart under a new pid is the same server to the
    /// user, and a manual Refresh can move an id while nothing stopped at all.
    public func departed(since previous: ScanResult, watching watched: Set<ServiceKey>) -> [RunningService] {
        let watchedPorts = Set(watched.map(\.port))
        // Ports first, because building a key standardises a path.
        func watchedServices(in result: ScanResult) -> [ServiceKey: RunningService] {
            let candidates = result.everyService.filter { watchedPorts.contains($0.port) }
            let keyed = candidates.compactMap { service in ServiceKey(service).map { ($0, service) } }
            return Dictionary(keyed.filter { watched.contains($0.0) }, uniquingKeysWith: { first, _ in first })
        }
        guard !watched.isEmpty else { return [] }
        let before = watchedServices(in: previous)
        let live = watchedServices(in: self)
        return before.filter { live[$0.key] == nil }.map(\.value).sorted { $0.port < $1.port }
    }
}
