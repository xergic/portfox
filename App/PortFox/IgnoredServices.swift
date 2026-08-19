import Foundation
import Observation
import PortFoxKit

/// Services the user has chosen not to see, keyed by port and project or binary.
///
/// Kept in the app rather than in the kit for the reason `ProjectIconOverrides`
/// gives: this is a preference, not a fact about the machine. `ServiceRepository`
/// never learns about it, so the scan cache stays valid and ignoring costs no
/// rescan. `portfox-scan` keeps reporting every listener, which is what a CLI
/// should do.
///
/// Unlike `ProjectIconOverrides` nothing is pruned here. A stopped process proves
/// nothing about whether the user still wants it hidden, and the only cheap test,
/// does the executable still exist, drops valid entries mid-Homebrew-upgrade or on
/// an unmounted volume. Removal is explicit, through the Preferences list.
@MainActor
@Observable
final class IgnoredServices {
    private static let defaultsKey = "ignoredServices"

    /// Keyed rather than a list, so `contains` is O(1) on the scan path and there
    /// is only one collection to keep correct. Order is not kept because the only
    /// reader, the Preferences list, sorts by port.
    private var store: [IgnoreKey: IgnoredService]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.defaultsKey)
        let decoded = stored.flatMap { try? JSONDecoder().decode([IgnoredService].self, from: $0) } ?? []
        store = Dictionary(decoded.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var entries: [IgnoredService] { Array(store.values) }

    var isEmpty: Bool { store.isEmpty }

    /// The empty check comes first because it is the usual answer, and building a
    /// key means standardising a path once per service on every scan tick.
    func contains(_ service: RunningService) -> Bool {
        guard !store.isEmpty, let key = IgnoreKey(service) else { return false }
        return store[key] != nil
    }

    /// False when the service gave up nothing durable to key on, which is why the
    /// Ignore action is hidden rather than offered and silently ignored.
    func canIgnore(_ service: RunningService) -> Bool { IgnoreKey(service) != nil }

    func ignore(_ service: RunningService) {
        guard let entry = IgnoredService(service) else { return }
        store[entry.key] = entry
        commit()
    }

    func stopIgnoring(_ service: RunningService) {
        guard let key = IgnoreKey(service) else { return }
        remove(key)
    }

    func remove(_ key: IgnoreKey) {
        guard store.removeValue(forKey: key) != nil else { return }
        commit()
    }

    private func commit() {
        defaults.set(try? JSONEncoder().encode(entries), forKey: Self.defaultsKey)
    }
}
