import PortFoxKit
import SwiftUI

struct ServiceRowView: View {
    @Environment(AppState.self) private var state

    let service: RunningService
    /// Snapshot rendering has no pointer, so the hover state is forced there.
    var forcedHover = false

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            ServiceIconView(type: service.type)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(service.displayName)
                        .font(.portName)
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let version = service.version {
                        VersionLabel(text: version)
                    }
                }
                if let location = service.locationLabel {
                    Text(location)
                        .font(.portSubtitle)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .layoutPriority(1)
            .padding(.trailing, Theme.Metrics.rowActionsWidth)

            Spacer(minLength: 0)

            PortPill(port: service.port)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        // Overlaid beside the port pill rather than inserted into the stack, so
        // showing the actions never re-truncates the text under the pointer.
        .overlay(alignment: .trailing) {
            if showsActions {
                HoverActionsView(service: service)
                    .padding(.trailing, Theme.Metrics.portPillWidth + 14)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.Metrics.rowRadius, style: .continuous)
                .fill(showsActions ? Theme.cardHover : .clear)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Metrics.rowRadius, style: .continuous)
                        .strokeBorder(showsActions ? Theme.border : .clear, lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .onTapGesture { state.open(service) }
        .contextMenu { ServiceContextMenu(service: service) }
        .opacity(state.isBusy(service) ? 0.5 : 1)
    }

    private var showsActions: Bool { isHovering || forcedHover }
}

/// The version of the thing that is running, beside its name.
struct VersionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.portVersion)
            .foregroundStyle(Theme.tertiaryText)
            .lineLimit(1)
            .fixedSize()
    }
}

private struct ServiceContextMenu: View {
    @Environment(AppState.self) private var state
    let service: RunningService

    var body: some View {
        if service.localURL != nil {
            Button("Open in Browser") { state.open(service) }
            Button("Copy URL") { state.copyURL(service) }
        } else {
            Button("Copy Port") { state.copyURL(service) }
        }
        if service.revealDirectory != nil {
            Button("Reveal in Finder") { state.reveal(service) }
        }
        Divider()
        Button("Stop") { Task { await state.stop(service) } }
        if state.isStubborn(service) {
            Button("Force Stop") { Task { await state.forceStop(service) } }
        }
        Divider()
        Text("PID \(service.listenerProcess.pid) · stops \(service.rootProcess.pid)")
    }
}
