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
            .background(CardBackground())
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
            .font(.portCaption)
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.pill)
            )
    }

    /// The address is the one part a user copies, so it alone stays monospace.
    private var socketLine: Text {
        // A port is an identifier, not a quantity. Locale grouping renders
        // 3111 as "3 111".
        let host = Text("\(service.primarySocket.displayHost):").foregroundStyle(Theme.secondaryText)
        let port = Text(String(service.port)).foregroundStyle(Theme.primaryText)
        let started = service.listenerProcess.startTime.map { " · Started \(Uptime.label(since: $0))" } ?? ""
        return (Text("Listening on ") + (host + port).font(.portSubtitle) + Text(" (TCP)\(started)"))
            .font(.portDetail)
            .foregroundStyle(Theme.secondaryText)
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
            if service.hasHostProcess {
                stopButton
            }
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
