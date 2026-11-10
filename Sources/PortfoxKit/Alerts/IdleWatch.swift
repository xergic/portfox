import Foundation

/// Which agent-started servers have done nothing for long enough to mention.
///
/// Counted in elapsed time the caller measures between samples, never in wall
/// dates. A Mac that slept through the night would otherwise wake to a banner
/// for every server, each one idle for nine hours of nothing at all.
///
/// A server is busy in an interval when it burned at least `busyPercent` of a
/// core, workers included, or when a connection appeared that was not open at
/// the previous sample. A lone short request between two samples shows only
/// through the CPU it cost, which is why the window is an hour, not a minute.
public struct IdleWatch: Equatable, Sendable {
    public struct Reading: Equatable, Sendable {
        /// Nil on the first sample of a process, when there is no pair to measure.
        public let cpuPercent: Int?
        /// Remote ports of the connections open to the server right now.
        public let peers: Set<Int>

        public init(cpuPercent: Int?, peers: Set<Int>) {
            self.cpuPercent = cpuPercent
            self.peers = peers
        }
    }

    static let busyPercent = 1

    private struct Server: Equatable {
        var peers: Set<Int>
        var idleFor = Duration.zero
        var warned = false
    }

    private var servers: [String: Server] = [:]

    public init() {}

    /// The ids that have just reached `threshold`. Each is returned once, and
    /// again only after the server has been busy in between.
    public mutating func update(_ readings: [String: Reading], elapsed: Duration, threshold: Duration) -> [String] {
        var next: [String: Server] = [:]
        var reached: [String] = []
        for (id, reading) in readings.sorted(by: { $0.key < $1.key }) {
            guard var server = servers[id] else {
                next[id] = Server(peers: reading.peers)
                continue
            }

            let isBusy = (reading.cpuPercent ?? 0) >= Self.busyPercent || !reading.peers.isSubset(of: server.peers)
            server.peers = reading.peers
            if isBusy {
                server.idleFor = .zero
                server.warned = false
            } else {
                server.idleFor += elapsed
                if server.idleFor >= threshold, !server.warned {
                    server.warned = true
                    reached.append(id)
                }
            }
            next[id] = server
        }
        servers = next
        return reached
    }
}
