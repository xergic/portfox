import Foundation

/// One ignored service, carrying enough identity from the moment it was ignored
/// to list in Preferences while nothing is running on that port. The key alone
/// would render as a bare path.
public struct IgnoredService: Codable, Hashable, Sendable, Identifiable {
    public var id: ServiceKey { key }

    public let key: ServiceKey
    /// `RunningService.displayName` when it was ignored.
    public let name: String
    /// `RunningService.subtitle` when it was ignored, else the anchor's name.
    public let detail: String

    public var port: Int { key.port }

    public init(key: ServiceKey, name: String, detail: String) {
        self.key = key
        self.name = name
        self.detail = detail
    }

    public init?(_ service: RunningService) {
        guard let key = ServiceKey(service) else { return nil }
        self.init(key: key, name: service.displayName, detail: service.subtitle ?? key.anchorName)
    }
}
