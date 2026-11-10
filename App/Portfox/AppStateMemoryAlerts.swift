import Foundation
import PortfoxKit

@MainActor
extension AppState {
    /// Read by the preferences checkbox. Switching it on is the one moment it may
    /// ask macOS for banners, the same as watching a service.
    var warnsAboutMemory: Bool {
        get { memoryAlerts.isEnabled }
        set {
            memoryAlerts.isEnabled = newValue
            askForBanners(whenEnabling: newValue)
        }
    }

    func askForBanners(whenEnabling isOn: Bool) {
        if isOn, !notifier.isAuthorized {
            Task { await notifier.requestAuthorization() }
        }
    }

    /// Dev servers with a process on this Mac, which is what both warnings measure.
    var hostedDevServers: [RunningService] { stoppableServices.filter(\.hasHostProcess) }

    /// Whether memory has to be sampled with every window closed.
    var isWatchingMemory: Bool { memoryAlerts.isEnabled && notifier.isAuthorized }

    /// Dev servers only, the same line Stop All draws. A database is sized by
    /// whoever configured it, and a banner about Postgres's buffers helps nobody.
    func checkMemory(_ sampled: [pid_t: TaskSample], workers: [pid_t: [pid_t]]) {
        guard isWatchingMemory else { return }

        let servers = hostedDevServers
        let usage = MemoryWatch.Usage(of: servers, workers: workers, sampled: sampled)
        for crossing in memoryAlerts.crossings(usage) {
            switch crossing {
            case let .service(id, bytes):
                guard let server = servers.first(where: { $0.id == id }) else { continue }
                notifier.postMemoryWarning(
                    title: "\(server.displayName) is using \(ByteFormat.short(bytes))",
                    body: [server.project?.name, "Port \(server.port)", "over your \(memoryAlerts.perServiceGB) GB limit"]
                        .compactMap { $0 }
                        .joined(separator: " · ")
                )
            case let .total(bytes):
                notifier.postMemoryWarning(
                    title: "Dev servers are using \(ByteFormat.short(bytes))",
                    body: "\(servers.count) servers together, over your \(memoryAlerts.totalGB) GB limit"
                )
            }
        }
    }
}
