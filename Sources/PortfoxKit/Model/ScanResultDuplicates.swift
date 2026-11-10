import Foundation

extension ScanResult {
    /// Each later copy of a dev server, mapped to the port of the first copy.
    ///
    /// A copy is the same `ServiceType` running in the same service directory
    /// under a different root process. An agent that never noticed `next dev`
    /// already on 3000 starts a second one, which takes 3001 and serves the same
    /// code. The oldest root is the original, because that is the one the
    /// browser, the bookmarks and the other agent are already talking to.
    ///
    /// Two packages of one monorepo are not copies: each has its own directory.
    public var duplicateOriginalPorts: [RunningService.ID: Int] {
        let candidates = services.filter { service in
            service.classification == .developmentService && service.hasHostProcess
                && service.projectIdentifiesService
        }
        let copies = Dictionary(grouping: candidates) { DuplicateKey(type: $0.type, anchor: ServiceKey($0)?.anchor) }

        var originals: [RunningService.ID: Int] = [:]
        for group in copies.values where group.count > 1 {
            guard let original = group.min(by: { Self.age($0) < Self.age($1) }) else { continue }
            for copy in group where copy.rootProcess.pid != original.rootProcess.pid {
                originals[copy.id] = original.port
            }
        }
        return originals
    }

    /// An unknown start time sorts last, so a process that refused `proc_pidinfo`
    /// is never preferred as the original over one whose age is known.
    private static func age(_ service: RunningService) -> (Date, pid_t) {
        (service.rootProcess.startTime ?? .distantFuture, service.rootProcess.pid)
    }
}

private struct DuplicateKey: Hashable {
    let type: ServiceType
    let anchor: String?
}
