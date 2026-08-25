import Foundation

/// Splitting one forwarder's listening sockets across the containers that
/// published them.
///
/// A free function rather than a method on `ServiceRepository`, so it can be
/// tested without constructing the actor, the same reason
/// `ServiceRepository.representative` is a static.
public enum ContainerAttribution {
    public struct Attribution: Sendable {
        /// Containers that own at least one live socket, lowest host port first.
        public let owned: [(container: ContainerSnapshot, sockets: [ListeningSocket])]
        /// Sockets no container published. Kept so Docker Desktop's own API port,
        /// or an OrbStack machine port, becomes a plain Docker row rather than
        /// vanishing from the list.
        public let residual: [ListeningSocket]
    }

    /// Matched on host port alone, never on host address.
    ///
    /// docker reports `0.0.0.0`, `::` or `[::]` where lsof reports `*`, which
    /// `ListenerScanner.parseAddress` normalises to `0.0.0.0`. Comparing
    /// addresses could therefore only ever lose a row. The kernel will not let two
    /// containers publish the same host port, so the port is unambiguous on its own.
    public static func attribute(
        sockets: [ListeningSocket],
        to containers: [ContainerSnapshot]
    ) -> Attribution {
        var ownerByPort: [Int: ContainerSnapshot] = [:]
        for container in containers {
            for published in container.publishedPorts { ownerByPort[published.hostPort] = container }
        }

        var socketsByContainer: [ContainerSnapshot: [ListeningSocket]] = [:]
        var residual: [ListeningSocket] = []
        for socket in sockets {
            guard let owner = ownerByPort[socket.port] else {
                residual.append(socket)
                continue
            }
            socketsByContainer[owner, default: []].append(socket)
        }

        // Ordered, so two scans of an unchanged machine produce the rows in the
        // same order and the list does not shuffle under the pointer.
        let owned = socketsByContainer
            .map { (container: $0.key, sockets: $0.value.sorted { $0.port < $1.port }) }
            .sorted { lhs, rhs in
                let left = lhs.sockets[0].port
                let right = rhs.sockets[0].port
                if left != right { return left < right }
                return lhs.container.id < rhs.container.id
            }

        return Attribution(owned: owned, residual: residual)
    }
}
