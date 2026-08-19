import PortFoxKit
import SwiftUI

/// Live memory readouts, each reading the sample itself.
///
/// Resident memory is resampled on every tick, so whichever view reads it is
/// invalidated every tick. Keeping the read in a leaf means a tick redraws a
/// `Text` rather than the pane, the detail card or the whole process tree that
/// would otherwise contain the read.

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
