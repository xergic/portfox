import PortfoxKit
import SwiftUI

/// The actions a hovered row shows in place of its pills.
struct HoverActionsView: View {
    @Environment(AppState.self) private var state
    let service: RunningService
    @Binding var isSharing: Bool

    var body: some View {
        HStack(spacing: 1) {
            if service.localURL != nil {
                IconButton(symbol: "globe", help: "Open in browser") { state.open(service) }
            }
            IconButton(symbol: "doc.on.doc", help: service.localURL == nil ? "Copy port" : "Copy URL") {
                state.copyURL(service)
            }
            // Only for a web service another device can reach. A phone camera opens
            // a URL, and nothing else on this row means anything to it.
            if service.type.isHTTP, service.networkPort != nil {
                IconButton(symbol: "qrcode", help: "Open on your phone") { isSharing = true }
                    .popover(isPresented: $isSharing, arrowEdge: .bottom) { LANShareView(service: service) }
            }
            if service.revealDirectory != nil {
                IconButton(symbol: "folder", help: "Reveal in Finder") { state.reveal(service) }
            }
            // Signalling a container row would take down the forwarder every
            // other container publishes through, so `ProcessController` refuses
            // it. Offering a button that always refuses would be worse.
            if service.hasHostProcess {
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
        }
        .fixedSize()
    }
}
