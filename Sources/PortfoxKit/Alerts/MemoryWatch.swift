import Foundation

/// Which dev servers are over a memory limit, and which only just crossed it.
///
/// A value, so the app keeps one and the policy is tested without a machine.
/// One banner per crossing: a server stays "over" until it falls back below
/// `rearmFraction` of the limit, so one hovering at 4.0 GB does not post a
/// banner on every sample.
public struct MemoryWatch: Equatable, Sendable {
    public struct Limits: Equatable, Sendable {
        public var perService: UInt64
        public var total: UInt64

        public init(perService: UInt64, total: UInt64) {
            self.perService = perService
            self.total = total
        }
    }

    public enum Crossing: Equatable, Sendable {
        case service(id: String, bytes: UInt64)
        case total(bytes: UInt64)
    }

    /// Each service's resident memory with its workers, and the total with every
    /// pid counted once, because two services can share one.
    public struct Usage: Equatable, Sendable {
        public let byService: [String: UInt64]
        public let total: UInt64

        public init(byService: [String: UInt64], total: UInt64) {
            self.byService = byService
            self.total = total
        }

        /// A service counts its workers, because a Next.js dev server's memory
        /// sits in the compile workers under the process holding the socket.
        public init(of services: [RunningService], workers: [pid_t: [pid_t]], sampled: [pid_t: TaskSample]) {
            var byService: [String: UInt64] = [:]
            var counted: Set<pid_t> = []
            var total: UInt64 = 0
            for service in services {
                let listener = service.listenerProcess.pid
                let pids = [listener] + (workers[listener] ?? [])
                byService[service.id] = pids.reduce(0) { $0 + (sampled[$1]?.residentBytes ?? 0) }
                for pid in pids where counted.insert(pid).inserted {
                    total += sampled[pid]?.residentBytes ?? 0
                }
            }
            self.init(byService: byService, total: total)
        }
    }

    static let rearmFraction = 0.9

    private var overServiceIDs: Set<String> = []
    private var isOverTotal = false

    public init() {}

    public mutating func update(_ usage: Usage, limits: Limits) -> [Crossing] {
        var crossings: [Crossing] = []
        let total = usage.total

        overServiceIDs.formIntersection(usage.byService.keys)
        for (id, bytes) in usage.byService.sorted(by: { $0.key < $1.key }) {
            if overServiceIDs.contains(id) {
                if Self.hasFallenBack(bytes, below: limits.perService) { overServiceIDs.remove(id) }
            } else if bytes >= limits.perService {
                overServiceIDs.insert(id)
                crossings.append(.service(id: id, bytes: bytes))
            }
        }

        if isOverTotal {
            if Self.hasFallenBack(total, below: limits.total) { isOverTotal = false }
        } else if total >= limits.total {
            isOverTotal = true
            crossings.append(.total(bytes: total))
        }
        return crossings
    }

    private static func hasFallenBack(_ bytes: UInt64, below limit: UInt64) -> Bool {
        Double(bytes) < Double(limit) * rearmFraction
    }
}
