import Foundation
import PortfoxKit

/// Memory and CPU, read by leaf views so a sample redraws a label, not a list.
@MainActor
extension AppState {
    func memory(of pid: pid_t) -> UInt64? { metrics.memory(of: pid) }
    func cpu(of pid: pid_t) -> Int? { metrics.cpu(of: pid) }

    /// A service's whole share of the CPU, summed at sample time. Empty while the
    /// preference is off, so a label reads it without depending on the preference.
    func cpu(ofServiceAt pid: pid_t) -> Int? { metrics.cpuIncludingWorkers(of: pid) }

    /// Resident memory of every visible service's listener, which is what the
    /// dashboard header reports. Workers are excluded, so this is a floor.
    ///
    /// Over a set of pids, not of services. Every container behind one forwarder
    /// is its own row pointing at the same process, so summing per row would
    /// report an eight-container stack's forwarder eight times.
    var watchedMemoryBytes: UInt64 {
        Set(result.services.map(\.listenerProcess.pid))
            .reduce(0) { $0 + (metrics.memory(of: $1) ?? 0) }
    }

    func sampleTasks() async {
        guard let tree = processTree, wantsMemory || wantsCPU || isWatchingMemory else {
            metrics.forgetEverything()
            return
        }

        // Ignored services are sampled too, so one selected under the Ignored chip
        // still reports its numbers in the detail pane. They stay out of
        // `watchedMemoryBytes`, which is the total the user asked to be rid of.
        let watched = result.services + ignoredResult.services
        // A set, because relatives include ancestors and two services under one
        // shell would otherwise be asked about the same pid twice.
        let pids = Set(watched.flatMap { tree.relatives(of: $0.listenerProcess.pid) })
        guard !pids.isEmpty else {
            metrics.forgetEverything()
            return
        }

        // Walked once here rather than once per row per redraw, which is also what
        // keeps a CPU label from depending on the tree.
        var workersByListener: [pid_t: [pid_t]] = [:]
        if wantsCPU || isWatchingMemory {
            for service in watched {
                let listener = service.listenerProcess.pid
                workersByListener[listener] = tree.descendants(of: listener).map(\.pid)
            }
        }

        let sampled = await repository.sampleTasks(of: pids)
        checkMemory(sampled, workers: workersByListener)
        metrics.absorb(
            sampled,
            workersByListener: workersByListener,
            keepingMemory: wantsMemory,
            keepingCPU: wantsCPU
        )
    }
}
