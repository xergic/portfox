import Foundation
import PortfoxKit

@MainActor
extension AppState {
    func sessionTitle(for service: RunningService) -> String? {
        service.listenerProcess.agentSession.flatMap { sessionTitles[$0.sessionID] }
    }

    /// Off the main actor, because a Claude Code session file is read from its
    /// tail and there can be hundreds of project folders to look in. Only hits
    /// are kept, so a session that has no title yet is asked again next scan.
    func loadSessionTitles(for services: [RunningService]) {
        let missing = Set(services.filter(\.isAgentStarted).compactMap(\.listenerProcess.agentSession))
            .filter { sessionTitles[$0.sessionID] == nil }
        guard !missing.isEmpty else { return }
        Task {
            let found = await Task.detached(priority: .utility) {
                let titles = AgentSessionTitles()
                return missing.reduce(into: [String: String]()) { found, marker in
                    found[marker.sessionID] = titles.title(for: marker)
                }
            }.value
            if !found.isEmpty { sessionTitles.merge(found) { _, new in new } }
        }
    }
}
