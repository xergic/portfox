import PortfoxKit
import SwiftUI

/// The banner at the top of a service detail pane: icon, name, socket, and the
/// primary actions. Deliberately not a card, so the cards below it read as the
/// detail and this reads as the subject.
struct ServiceHeaderView: View {
    @Environment(AppState.self) private var state
    let service: RunningService
    var projectIconPath: String?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            iconBadge
            VStack(alignment: .leading, spacing: 4) {
                titleLine
                socketLine
            }
            Spacer(minLength: 12)
            actions
        }
        .opacity(state.isBusy(service) ? 0.5 : 1)
    }

    private var iconBadge: some View {
        ServiceIconView(type: service.type, projectIconPath: projectIconPath, size: 32)
            .frame(width: 46, height: 46)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.border, lineWidth: 1)
                    )
            )
    }

    private var titleLine: some View {
        HStack(spacing: 8) {
            Text(service.displayName)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.primaryText)
            if let version = service.version {
                TrailingFact(text: version)
            }
            attributionPill
        }
    }

    /// A daemon has no project worth naming, so it is labelled with where it was
    /// installed from. DBngin's Postgres would otherwise headline with its data
    /// directory, a bare UUID.
    @ViewBuilder
    private var attributionPill: some View {
        if service.projectIdentifiesService, let project = service.project {
            pill(text: "Project: \(project.name)")
        } else if let source = service.installationSource {
            pill(text: source)
        }
    }

    private func pill(text: String) -> some View {
        Text(text)
            .font(.mono(10))
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.pill)
            )
    }

    private var socketLine: Text {
        // A port is an identifier, not a quantity. Locale grouping renders
        // 3111 as "3 111".
        let host = Text("Listening on \(service.primarySocket.displayHost):")
            .foregroundStyle(Theme.secondaryText)
        let port = Text(String(service.port)).foregroundStyle(Theme.primaryText)
        let socketKind = Text(" (TCP)").foregroundStyle(Theme.secondaryText)
        let base = host + port + socketKind
        let started = service.listenerProcess.startTime.map {
            Text(" · Started \(Uptime.label(since: $0))").foregroundStyle(Theme.secondaryText)
        }
        return (started.map { base + $0 } ?? base).font(.portSubtitle)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            ActionButton(symbol: "doc.on.doc", label: copyLabel, tint: Theme.primaryText) {
                state.copyURL(service)
            }
            if service.localURL != nil {
                ActionButton(symbol: "globe", label: "Open Browser", isPrimary: true) {
                    state.open(service)
                }
            }
            if state.canRestart, state.relaunchableServiceIDs.contains(service.id) {
                ActionButton(symbol: "arrow.clockwise", label: "Restart", tint: Theme.primaryText) {
                    Task { await state.restart(service) }
                }
            }
            stopButton
        }
    }

    private var copyLabel: String { service.localURL == nil ? "Copy Port" : "Copy URL" }

    private var stopButton: some View {
        state.isStubborn(service)
            ? ActionButton(symbol: "stop.fill", label: "Force Stop", tint: Theme.danger) {
                Task { await state.forceStop(service) }
            }
            : ActionButton(symbol: "stop.fill", label: "Stop", tint: Theme.danger) {
                Task { await state.stop(service) }
            }
    }
}

/// Shared chrome for the header card's action buttons. The primary variant is
/// filled with the accent colour; every other button shares the same
/// secondary, outlined pill and is told apart by its icon and tint.
private struct ActionButton: View {
    let symbol: String
    let label: String
    var isPrimary = false
    var tint: Color = Theme.primaryText
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(isPrimary ? Theme.onAccent : tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isPrimary ? Theme.accent : Theme.cardHover)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(isPrimary ? .clear : Theme.border, lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
