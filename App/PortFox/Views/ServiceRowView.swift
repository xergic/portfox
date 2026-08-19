import PortFoxKit
import SwiftUI

struct ServiceRowView: View {
    @Environment(AppState.self) private var state

    let service: RunningService
    var layout: ServiceCellLayout = .serviceFirst
    var showsHoverActions = true
    var isSelected = false
    /// Nil opens the service in a browser. The dashboard passes a selection
    /// handler instead, since clicking a sidebar row should not launch anything.
    var onTap: ((RunningService) -> Void)?
    /// Snapshot rendering has no pointer, so the hover state is forced there.
    var forcedHover = false

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            leadingIcon

            VStack(alignment: .leading, spacing: 1) {
                switch effectiveLayout {
                case .serviceFirst:
                    serviceLine
                    folderLine
                case .projectFirst:
                    projectLine
                    serviceLine
                }
            }
            .layoutPriority(1)
            // Reserved only where the actions can actually appear. The dashboard
            // selects rather than hovers, so there it is 72 points of wasted width.
            .padding(.trailing, showsHoverActions ? Theme.Metrics.rowActionsWidth : 0)

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
                .fill(isHighlighted ? Theme.cardHover : .clear)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Metrics.rowRadius, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: isSelected ? 1.5 : 1)
                )
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .onTapGesture {
            if let onTap { onTap(service) } else { state.open(service) }
        }
        .contextMenu { ServiceContextMenu(service: service) }
        .opacity(state.isBusy(service) ? 0.5 : 1)
    }

    /// Project-first leads with the project's own icon, which is usually its
    /// favicon, and falls back to the framework logo when there is none.
    private var leadingIcon: some View {
        ServiceIconView(
            type: service.type,
            projectIconPath: effectiveLayout == .projectFirst ? service.project?.iconPath : nil
        )
    }

    private var serviceLine: some View {
        HStack(spacing: 5) {
            if effectiveLayout == .projectFirst {
                ServiceIconView(type: service.type, size: Theme.Metrics.serviceIconSmall)
            }
            Text(service.displayName)
                .font(effectiveLayout == .projectFirst ? .portSubtitle : .portName)
                .foregroundStyle(effectiveLayout == .projectFirst ? Theme.secondaryText : Theme.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            if let version = service.version {
                VersionLabel(text: version)
            }
        }
    }

    private var projectLine: some View {
        HStack(spacing: 5) {
            Text(projectTitle)
                .font(.portName)
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            if let version = service.project?.version {
                VersionLabel(text: "@ \(version)", fixed: false)
            }
        }
    }

    // Two labels rather than one string, so the version reads as secondary to the
    // folder in the same way it does beside the service name, and so the folder is
    // what survives truncation.
    private var folderLine: some View {
        HStack(spacing: 4) {
            if let subtitle = service.subtitle {
                Text(subtitle)
                    .font(.portSubtitle)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
            }
            if let version = service.project?.version {
                VersionLabel(text: "@ \(version)", fixed: false)
            }
        }
    }

    /// The per-service project name, not the group heading. In a sibling group the
    /// heading reads `Wishfox` while each row names its own repository.
    private var projectTitle: String {
        service.project?.name ?? service.displayName
    }

    /// A daemon never leads with a project, because whatever was resolved is an
    /// accident of where it happens to run. DBngin's Postgres would headline with
    /// its data directory, a bare UUID, and Homebrew's with `homebrew`, since the
    /// Homebrew prefix is itself a git repository.
    private var effectiveLayout: ServiceCellLayout {
        guard let project = service.project, project.rootKind != .directory else { return .serviceFirst }
        switch service.type.category {
        case .database, .infrastructure, .unknown: return .serviceFirst
        case .web, .api, .tooling: return layout
        }
    }

    private var showsActions: Bool { showsHoverActions && (isHovering || forcedHover) }
    private var isHighlighted: Bool { showsActions || isSelected || (isHovering && !showsHoverActions) }
    private var borderColor: Color {
        if isSelected { return Theme.accent }
        return isHighlighted ? Theme.border : .clear
    }
}

/// The version of the thing that is running, beside its name.
struct VersionLabel: View {
    let text: String
    /// Beside a service name the version must never shrink, since the name can
    /// truncate instead. Beside a folder it is the version that gives way.
    var fixed = true

    var body: some View {
        Text(text)
            .font(.portVersion)
            .foregroundStyle(Theme.tertiaryText)
            .lineLimit(1)
            .truncationMode(.tail)
            .fixedSize(horizontal: fixed, vertical: false)
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
        if state.canIgnore(service) {
            Divider()
            if state.isIgnored(service) {
                Button("Stop Ignoring") { state.stopIgnoring(service) }
            } else {
                Button("Ignore Service") { state.ignore(service) }
            }
        }
        Divider()
        Text("PID \(service.listenerProcess.pid) · stops \(service.rootProcess.pid)")
    }
}
