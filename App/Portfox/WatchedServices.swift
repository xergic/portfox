import Foundation
import Observation
import PortfoxKit

/// Services the user wants to hear about when they stop, keyed like the ignore
/// list so the choice survives a restart of the server and of the app.
@MainActor
@Observable
final class WatchedServices {
    private static let defaultsKey = "watchedServices"

    private(set) var keys: Set<ServiceKey> {
        didSet { ports = Set(keys.map(\.port)) }
    }
    /// Checked before a key is built, because building one standardises a path
    /// and every row asks on every redraw.
    @ObservationIgnored private var ports: Set<Int> = []
    private let defaults: UserDefaults

    /// Services Portfox itself was asked to stop. The user pressed Stop, so a
    /// banner saying it stopped would be noise.
    @ObservationIgnored private var expectedDepartures = Expectations<ServiceKey>(window: .seconds(30))

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.defaultsKey)
        keys = Set(stored.flatMap { try? JSONDecoder().decode([ServiceKey].self, from: $0) } ?? [])
        ports = Set(keys.map(\.port))
    }

    func contains(_ service: RunningService) -> Bool {
        guard ports.contains(service.port), let key = ServiceKey(service) else { return false }
        return keys.contains(key)
    }

    func setWatched(_ watched: Bool, for service: RunningService) {
        guard let key = ServiceKey(service) else { return }
        if watched { keys.insert(key) } else { keys.remove(key) }
        defaults.set(try? JSONEncoder().encode(Array(keys)), forKey: Self.defaultsKey)
    }

    /// Called before anything is signalled, so the scan that notices the server
    /// is gone already knows it was asked to go.
    func expectDeparture(of service: RunningService) {
        guard contains(service), let key = ServiceKey(service) else { return }
        expectedDepartures.expect(key)
    }

    /// The departures nobody asked for.
    func unexpected(_ departed: [RunningService]) -> [RunningService] {
        departed.filter { service in
            guard let key = ServiceKey(service) else { return true }
            return !expectedDepartures.consume(key)
        }
    }
}
