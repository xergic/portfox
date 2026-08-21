import PortfoxKit
import SwiftUI

/// Live memory and CPU readouts, each reading the sample itself.
///
/// Both are resampled on every tick, so whichever view reads one is invalidated
/// every tick. Keeping the read in a leaf means a tick redraws a `Text` rather
/// than the pane, the detail card or the whole process tree that would otherwise
/// contain the read.

/// Total for every visible service, shown beside the dashboard title.
struct WatchedMemoryLabel: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if state.watchedMemoryBytes > 0 {
            Text("\(ByteFormat.short(state.watchedMemoryBytes)) watched")
                .font(.portSubtitle)
                .foregroundStyle(Theme.tertiaryText)
        }
    }
}

/// One process's memory, shown on a row of the process tree.
struct ProcessMemoryLabel: View {
    @Environment(AppState.self) private var state
    let pid: pid_t

    var body: some View {
        if let bytes = state.memory(of: pid) {
            Text(ByteFormat.short(bytes))
                .font(.portSubtitle)
                .foregroundStyle(Theme.tertiaryText)
        }
    }
}

/// The listener's memory, as a fact row inside the process metadata card.
struct ResidentMemoryRow: View {
    @Environment(AppState.self) private var state
    let pid: pid_t

    var body: some View {
        LabeledRow(label: "Resident memory", value: state.memory(of: pid).map(ByteFormat.short))
    }
}

/// One service's CPU, listener and workers together, shown on a list row.
struct ServiceCPULabel: View {
    @Environment(AppState.self) private var state
    let pid: pid_t

    var body: some View {
        if let percent = state.cpu(ofServiceAt: pid) {
            Text(CPUFormat.short(percent))
                .font(.portVersion)
                .foregroundStyle(percent >= 100 ? Theme.danger : Theme.tertiaryText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

/// One process's CPU, shown on a row of the process tree.
struct ProcessCPULabel: View {
    @Environment(AppState.self) private var state
    let pid: pid_t

    var body: some View {
        if let percent = state.cpu(of: pid) {
            Text(CPUFormat.short(percent))
                .font(.portSubtitle)
                .foregroundStyle(Theme.tertiaryText)
        }
    }
}

/// The service's CPU, as a fact row inside the process metadata card. Absent
/// rather than empty when the preference is off, since a permanent dash is a
/// worse answer than no row.
struct CPUUsageRow: View {
    @Environment(AppState.self) private var state
    let pid: pid_t

    var body: some View {
        if state.showsCPU {
            LabeledRow(label: "CPU", value: state.cpu(ofServiceAt: pid).map(CPUFormat.short))
        }
    }
}

enum CPUFormat {
    /// Percent of one core, as Activity Monitor reports it, so a service using
    /// four of them reads 400%.
    static func short(_ percent: Int) -> String { "\(percent)%" }
}
