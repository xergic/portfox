import Foundation
import PortfoxKit

/// Resident memory and CPU by pid, kept apart from the scan.
///
/// Both move on every sample. Holding them inside `ScanResult` would make two
/// scans of an unchanged machine compare unequal and redraw the whole dashboard
/// on a one second tick, so they live here and are read by leaf views instead.
///
/// Observable in its own right, so a tick that only moves a number invalidates
/// the labels reading it and nothing above them.
@MainActor
@Observable
final class ProcessMetrics {
    private(set) var memoryByPID: [pid_t: UInt64] = [:]
    /// Whole percent of one core, so a service on four of them reads 400.
    private(set) var cpuByPID: [pid_t: Int] = [:]
    /// A listener's percent with its workers' already added in, summed here at
    /// sample time rather than in the view.
    ///
    /// A row that walked the process tree to find its own workers would take a
    /// dependency on the tree, which is rewritten whenever any socket anywhere on
    /// the machine moves, and would then redraw on ticks where its own number
    /// never changed.
    private(set) var cpuByListenerPID: [pid_t: Int] = [:]

    /// The previous sample each percent is measured against. CPU time is a
    /// counter, so a single reading says only how much work a process has ever
    /// done, which is not what anyone wants to know.
    private var previousTasks: [pid_t: TaskSample] = [:]
    private var previousTakenAt: ContinuousClock.Instant?

    func memory(of pid: pid_t) -> UInt64? { memoryByPID[pid] }

    /// Nil until a second sample exists to measure against, which is why a row
    /// stays blank for one tick after CPU is switched on, and stays blank forever
    /// with the refresh loop switched off.
    func cpu(of pid: pid_t) -> Int? { cpuByPID[pid] }

    /// A service's whole share of the CPU: its listener plus its workers.
    ///
    /// The listener alone is the wrong number. A Next.js dev server idles in the
    /// parent while a compile worker burns a core, and a row reading 0% next to a
    /// fan at full speed is worse than no row at all.
    func cpuIncludingWorkers(of listener: pid_t) -> Int? { cpuByListenerPID[listener] }

    /// Takes a fresh sample apart into the two readings, keeping only the ones
    /// something is drawing.
    ///
    /// Every write is guarded by a comparison. `@Observable` notifies whether or
    /// not the value moved, and an idle machine must not redraw once a second.
    func absorb(
        _ sampled: [pid_t: TaskSample],
        workersByListener: [pid_t: [pid_t]],
        keepingMemory: Bool,
        keepingCPU: Bool
    ) {
        if keepingMemory {
            let memory = sampled.mapValues(\.residentBytes)
            if memory != memoryByPID { memoryByPID = memory }
        } else {
            forgetMemory()
        }

        if keepingCPU {
            updateCPU(with: sampled, workersByListener: workersByListener)
        } else {
            forgetCPU()
        }
    }

    func forgetEverything() {
        forgetMemory()
        forgetCPU()
    }

    func forgetMemory() {
        if !memoryByPID.isEmpty { memoryByPID = [:] }
    }

    func forgetCPU() {
        if !cpuByPID.isEmpty { cpuByPID = [:] }
        if !cpuByListenerPID.isEmpty { cpuByListenerPID = [:] }
        previousTasks = [:]
        previousTakenAt = nil
    }

    private func updateCPU(with sampled: [pid_t: TaskSample], workersByListener: [pid_t: [pid_t]]) {
        let now = ContinuousClock.now
        defer {
            previousTasks = sampled
            previousTakenAt = now
        }
        guard let previous = previousTakenAt else { return }

        let percents = CPUUsage.percents(from: previousTasks, to: sampled, over: previous.duration(to: now))
        // Rounded to a whole percent before it gets here, so an idle process
        // compares equal tick after tick and redraws nothing.
        if percents != cpuByPID { cpuByPID = percents }

        var rolledUp: [pid_t: Int] = [:]
        rolledUp.reserveCapacity(workersByListener.count)
        for (listener, workers) in workersByListener {
            var total = percents[listener]
            for worker in workers {
                guard let percent = percents[worker] else { continue }
                total = (total ?? 0) + percent
            }
            rolledUp[listener] = total
        }
        if rolledUp != cpuByListenerPID { cpuByListenerPID = rolledUp }
    }
}
