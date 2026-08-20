import PortfoxKit
import SwiftUI

/// The action cluster that appears on row hover. Two further slots, detection
/// evidence and the process tree, are laid out in the design and deliberately
/// deferred past the MVP.
struct HoverActionsView: View {
    @Environment(AppState.self) private var state
    let service: RunningService

    var body: some View {
        HStack(spacing: 1) {
            if service.localURL != nil {
                IconButton(symbol: "globe", help: "Open in browser") { state.open(service) }
            }
            if service.revealDirectory != nil {
                IconButton(symbol: "folder", help: "Reveal in Finder") { state.reveal(service) }
            }
            if state.isStubborn(service) {
                IconButton(symbol: "stop.fill", tint: Theme.danger, help: "Force stop, it ignored SIGTERM") {
                    Task { await state.forceStop(service) }
                }
            } else {
                IconButton(symbol: "stop.fill", tint: Theme.danger, help: "Stop") {
                    Task { await state.stop(service) }
                }
            }
        }
        .fixedSize()
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.cardHover)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )
        )
    }
}
