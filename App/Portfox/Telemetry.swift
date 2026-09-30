import Foundation
import PortfoxKit
import TelemetryDeck

/// A closed `Signal` enum, so no call site can put a name, path or port into a
/// parameter.
@MainActor
enum Telemetry {
    enum Signal {
        case dashboardOpened
        case serviceStopped(RunningService)
        case serviceForceStopped(RunningService)
        case serviceRestarted(RunningService)
        case serviceInspected(RunningService)
        case serviceIgnored(RunningService)

        fileprivate var name: String {
            switch self {
            case .dashboardOpened: "Portfox.Dashboard.opened"
            case .serviceStopped: "Portfox.Service.stopped"
            case .serviceForceStopped: "Portfox.Service.forceStopped"
            case .serviceRestarted: "Portfox.Service.restarted"
            case .serviceInspected: "Portfox.Service.inspected"
            case .serviceIgnored: "Portfox.Service.ignored"
            }
        }

        fileprivate var parameters: [String: String] {
            switch self {
            case .dashboardOpened:
                [:]
            case .serviceStopped(let service), .serviceForceStopped(let service),
                 .serviceRestarted(let service), .serviceInspected(let service),
                 .serviceIgnored(let service):
                ["serviceType": service.type.rawValue, "category": service.type.category.rawValue]
            }
        }
    }

    static let defaultsKey = "sharesUsageData"

    /// Empty unless the release workflow sets `TELEMETRY_APP_ID`, so a fork or a
    /// local build never reports into the official dashboard.
    private static let appID = Bundle.main.object(forInfoDictionaryKey: "TelemetryAppID") as? String ?? ""
    private static var isRunning = false

    /// Off in a snapshot run, so `make snapshot` never sends anything. The SDK's
    /// `signal` builds a blank manager when none was initialised, which is why
    /// `send` checks `isRunning` instead of trusting the SDK to stay quiet.
    static func setEnabled(_ enabled: Bool) {
        guard enabled != isRunning else { return }
        if enabled {
            guard !appID.isEmpty, SnapshotRenderer.request == nil else { return }
            TelemetryDeck.initialize(config: .init(appID: appID))
        } else {
            TelemetryDeck.terminate()
        }
        isRunning = enabled
    }

    static func send(_ signal: Signal) {
        guard isRunning else { return }
        TelemetryDeck.signal(signal.name, parameters: signal.parameters)
    }
}
