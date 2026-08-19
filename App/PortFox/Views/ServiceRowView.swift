import PortFoxKit
import SwiftUI

struct ServiceRowView: View {
    @Environment(AppState.self) private var state

    let service: RunningService
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            ServiceIconView(type: service.type)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(service.displayName)
                        .font(.portName)
                        .foregroundStyle(Theme.primaryText)
                    if let confidence = uncertainConfidence {
                        ConfidenceChip(confidence: confidence)
                    }
                }
                if let subtitle = service.subtitle {
                    Text(subtitle)
                        .font(.portSubtitle)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 6)

            if isHovering {
                HoverActionsView(service: service)
                    .transition(.opacity)
            }
            PortPill(port: service.port)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: Theme.Metrics.rowRadius, style: .continuous)
                .fill(isHovering ? Theme.cardHover : .clear)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Metrics.rowRadius, style: .continuous)
                        .strokeBorder(isHovering ? Theme.border : .clear, lineWidth: 1)
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

    /// A confident detection needs no explanation. An uncertain one is worth
    /// flagging, which is what the percentage chips in the design are for.
    private var uncertainConfidence: Double? {
        let confidence = service.detection.confidence
        guard service.type != .unknown, confidence > 0, confidence < 0.9 else { return nil }
        return confidence
    }
}

private struct ConfidenceChip: View {
    let confidence: Double

    var body: some View {
        Text("\(Int((confidence * 100).rounded()))%")
            .font(.portChip)
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
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
