import Foundation

/// Resident memory of everything a stop is about to signal, taken just before
/// the signal, so the freed figure is what those processes held rather than a
/// guess from a later sample.
public struct StopFootprint: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public let identity: String
        public let bytes: UInt64
    }

    public let entries: [pid_t: Entry]

    public init(entries: [pid_t: Entry]) {
        self.entries = entries
    }

    /// The root and its descendants, each once. A container row is skipped:
    /// its process is the forwarder every other container shares. The tree can
    /// be hours old, so a pid another process now holds is never sampled.
    public static func measure(
        _ service: RunningService,
        tree: ProcessTree,
        currentIdentity: (pid_t) -> String?,
        sample: (pid_t) -> UInt64?
    ) -> StopFootprint {
        guard service.hasHostProcess else { return StopFootprint(entries: [:]) }
        let root = tree.process(service.rootProcess.pid) ?? service.rootProcess
        var entries: [pid_t: Entry] = [:]
        for process in [root] + tree.descendants(of: root.pid) {
            guard entries[process.pid] == nil, currentIdentity(process.pid) == process.identity,
                  let bytes = sample(process.pid) else { continue }
            entries[process.pid] = Entry(identity: process.identity, bytes: bytes)
        }
        return StopFootprint(entries: entries)
    }

    /// Bytes held by the processes that are gone. A pid now occupied by a
    /// different process counts as gone, which is why `isAlive` gets the identity.
    public func freed(isAlive: (pid_t, String) -> Bool) -> UInt64 {
        entries.reduce(0) { total, item in
            isAlive(item.key, item.value.identity) ? total : total + item.value.bytes
        }
    }
}
