import Foundation

/// Something the user is waiting on to come up.
public enum StartTarget: Hashable, Sendable {
    /// A project root, matched by any service at or below it.
    case project(root: String)
    case port(Int)
    /// Judged on arrivals rather than on the scan, because a server an agent
    /// started an hour ago is already running and answers nothing.
    case nextAgentServer
}

extension ScanResult {
    /// The service that answers `target`, if it is up. `appeared` is this
    /// scan's arrivals, which only `nextAgentServer` reads.
    public func service(answering target: StartTarget, appeared: [RunningService]) -> RunningService? {
        switch target {
        case .project(let root):
            let inProject = everyService.filter { $0.isInProject(at: root) }
            // The banner is for the thing the user will open. A database the
            // project brought up first is not it, and is never user-managed.
            return inProject.first { $0.localURL != nil } ?? inProject.first { $0.classification.isUserManaged }
        case .port(let port):
            return everyService.first { $0.sockets.contains { $0.port == port } }
        case .nextAgentServer:
            return appeared.first { service in
                guard case .agent = service.origin else { return false }
                return service.classification.isUserManaged
            }
        }
    }
}
