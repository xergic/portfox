import Foundation
import PortfoxKit

@MainActor
extension AppState {
    /// Switching it on is the one moment it may ask macOS for banners.
    var warnsAboutIdleServers: Bool {
        get { idleAlerts.isEnabled }
        set {
            idleAlerts.isEnabled = newValue
            askForBanners(whenEnabling: newValue)
        }
    }

    /// Measured without banner permission too, because the row's idle label
    /// needs no permission. Only the banner does.
    var isWatchingIdle: Bool { idleAlerts.isEnabled }

    /// Only servers an agent started. Those are the ones nobody remembers: the
    /// session ended, the server did not. A server the user started by hand is
    /// theirs to keep running for as long as they like.
    func checkIdle(_ sampled: [pid_t: TaskSample], workers: [pid_t: [pid_t]]) {
        guard isWatchingIdle else { return }

        let servers = hostedDevServers.filter(\.isAgentStarted)
        let (percents, elapsed) = idleAlerts.measure(sampled)
        var readings: [String: IdleWatch.Reading] = [:]
        for server in servers {
            let listener = server.listenerProcess.pid
            let cpu = ([listener] + (workers[listener] ?? [])).compactMap { percents[$0] }
            readings[server.id] = IdleWatch.Reading(
                cpuPercent: cpu.isEmpty ? nil : cpu.reduce(0, +),
                peers: idleAlerts.inspector.connectionPeers(pid: listener, port: server.port)
            )
        }

        let reached = idleAlerts.idle(readings, elapsed: elapsed)
        guard notifier.isAuthorized else { return }
        for id in reached {
            guard let server = servers.first(where: { $0.id == id }) else { continue }
            notifier.postIdle(server)
        }
    }

    /// The Stop on an idle banner. Only the very process it warned about: the
    /// banner can be clicked long after, and a server that replaced it on the
    /// same port is not the idle one. Gone means nothing to do.
    func stop(identifiedBy identity: String) async {
        guard let service = result.services.first(where: { $0.rootProcess.identity == identity }) else { return }
        await stop(service)
    }
}
