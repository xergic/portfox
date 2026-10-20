import Foundation
import Observation
import PortfoxKit

/// The HTTP status of each web service, read at moments the user would expect.
///
/// Never on the refresh tick. A probe every two seconds would put a request in
/// the server's log every two seconds, and `next dev` compiles a page on its
/// first hit. A service is probed when it appears and when a window opens, and
/// never twice inside `interval`, so a server costs one request per start plus
/// one per glance.
@MainActor
@Observable
final class HealthChecks {
    enum Reading: Equatable {
        case status(code: Int, latency: Duration)
        /// Refused, timed out or not HTTP. Drawn as nothing, because a server that
        /// only speaks WebSocket would otherwise read as broken.
        case unreachable
    }

    private(set) var readings: [String: Reading] = [:]

    /// Stamped before the request goes out, so a second trigger while one is in
    /// flight is already inside the interval. The probe times out long before it.
    @ObservationIgnored private var lastChecked: [String: ContinuousClock.Instant] = [:]
    private static let interval = Duration.seconds(30)
    private let probe = HTTPProbe()

    func check(_ services: [RunningService]) {
        let now = ContinuousClock.now
        for service in services {
            guard let url = service.localURL else { continue }
            if let last = lastChecked[service.id], now - last < Self.interval { continue }

            lastChecked[service.id] = now
            Task { [probe] in
                do {
                    record(try await probe.probe(url, readsBody: false), for: service)
                } catch {
                    store(.unreachable, for: service.id)
                }
            }
        }
    }

    /// Also fed by the dashboard's Inspect, so the pill never disagrees with the
    /// card the user just asked for.
    func record(_ result: HTTPProbeResult, for service: RunningService) {
        lastChecked[service.id] = .now
        store(.status(code: result.statusCode, latency: result.latency), for: service.id)
    }

    private func store(_ reading: Reading, for id: String) {
        if readings[id] != reading { readings[id] = reading }
    }

    /// A restarted server has a new id, so its old reading would describe a
    /// process that never answered it.
    func forget(missingFrom live: Set<String> = []) {
        lastChecked = lastChecked.filter { live.contains($0.key) }
        let kept = readings.filter { live.contains($0.key) }
        if kept.count != readings.count { readings = kept }
    }
}
