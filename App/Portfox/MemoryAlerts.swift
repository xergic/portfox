import Foundation
import Observation
import PortfoxKit

/// "Warn about memory use": the preference, its two limits, and which servers
/// have already had their banner.
///
/// On by default, unlike arrival banners, because it never prompts. It posts
/// only once macOS already lets Portfox notify, so a user who never allowed
/// banners never hears from it.
@MainActor
@Observable
final class MemoryAlerts {
    static let perServiceChoices = [2, 4, 8]
    static let totalChoices = [8, 12, 16, 24]

    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Key.isEnabled) }
    }

    var perServiceGB: Int {
        didSet { defaults.set(perServiceGB, forKey: Key.perServiceGB) }
    }

    var totalGB: Int {
        didSet { defaults.set(totalGB, forKey: Key.totalGB) }
    }

    @ObservationIgnored private var watch = MemoryWatch()
    private let defaults: UserDefaults

    private enum Key {
        static let isEnabled = "warnsAboutMemory"
        static let perServiceGB = "memoryLimitPerServiceGB"
        static let totalGB = "memoryLimitTotalGB"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Key.isEnabled: true, Key.perServiceGB: 4, Key.totalGB: 12])
        isEnabled = defaults.bool(forKey: Key.isEnabled)
        perServiceGB = defaults.integer(forKey: Key.perServiceGB)
        totalGB = defaults.integer(forKey: Key.totalGB)
    }

    func crossings(_ usage: MemoryWatch.Usage) -> [MemoryWatch.Crossing] {
        let limits = MemoryWatch.Limits(perService: Self.bytes(perServiceGB), total: Self.bytes(totalGB))
        return watch.update(usage, limits: limits)
    }

    private static func bytes(_ gigabytes: Int) -> UInt64 { UInt64(max(1, gigabytes)) << 30 }
}
