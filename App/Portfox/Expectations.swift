import Foundation

/// Things Portfox caused itself and must not report back as news, each excused
/// until a deadline. A deadline rather than a flag, because an action that did
/// not take effect must not silence a real event an hour later.
struct Expectations<Key: Hashable> {
    let window: Duration
    private var deadlines: [Key: ContinuousClock.Instant] = [:]

    init(window: Duration) { self.window = window }

    mutating func expect(_ key: Key) { deadlines[key] = .now + window }

    /// True once for an expectation that has not expired, which it then consumes.
    /// Bounded by the number of distinct keys, so nothing needs a sweep.
    mutating func consume(_ key: Key) -> Bool {
        guard let deadline = deadlines.removeValue(forKey: key) else { return false }
        return deadline > .now
    }
}
