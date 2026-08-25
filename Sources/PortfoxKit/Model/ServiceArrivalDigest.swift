import Foundation

/// What a notification says when services appear.
///
/// One digest per batch rather than one notification per service, because a
/// compose stack coming up would otherwise be eight banners in three seconds.
///
/// In the kit rather than the app so it can be tested. The app target has no
/// tests, and this is branching text that will rot quietly if nothing checks it.
public struct ServiceArrivalDigest: Sendable, Equatable {
    public let title: String
    public let body: String

    /// The number named individually before the tail is summarised.
    static let namedLimit = 3

    public init?(_ services: [RunningService]) {
        guard let first = services.first else { return nil }

        guard services.count > 1 else {
            title = "\(first.displayName) on port \(first.port)"
            body = first.project?.name ?? first.subtitle ?? ""
            return
        }

        title = "\(services.count) new services"
        let named = services.prefix(Self.namedLimit)
            .map { "\($0.displayName) :\($0.port)" }
            .joined(separator: ", ")
        let remaining = services.count - Self.namedLimit
        body = remaining > 0 ? "\(named), and \(remaining) more" : named
    }
}
