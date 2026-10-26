import PortfoxKit
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
    @State private var hasAppeared = false
    /// Holds the actions on screen while the QR popover is open, because the
    /// pointer leaves the row to reach it and the button would vanish under it.
    @State private var isSharing = false

    var body: some View {
        HStack(spacing: 10) {
            leadingIcon

            Group {
                // A line that does not fit falls back to two for this row alone.
                // `ViewThatFits` measures ideal widths, so nothing is truncated to
                // squeeze onto one line, and no badge is ever dropped for room.
                if state.compactRows {
                    ViewThatFits(in: .horizontal) { oneLine; twoLines }
                } else {
                    twoLines
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 0)

            trailingSlot
        }
        .padding(.horizontal, Theme.Metrics.listRowPaddingH)
        .padding(.vertical, Theme.Metrics.rowPaddingV(compact: state.compactRows))
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .onAppear { hasAppeared = true }
        .onTapGesture {
            if let onTap { onTap(service) } else { state.open(service) }
        }
        .contextMenu { ServiceContextMenu(service: service) }
        .opacity(state.isBusy(service) ? 0.5 : 1)
    }

    /// The arrival wash sits over the hover fill, so a row that is both flashing
    /// and hovered still lightens and still reveals its actions, and nothing
    /// shifts when the flash ends.
    ///
    /// In fast and out slow: the row has to announce itself, then get out of the
    /// way. Both fit inside `ServiceArrivals.flashDuration` with room to spare.
    private var rowBackground: some View {
        let shape = RoundedRectangle.row
        return shape
            .fill(isSelected ? Theme.selectedRow : (isHighlighted ? Theme.cardHover : .clear))
            .overlay(shape.fill(Theme.arrivalRow).opacity(showsArrival ? 1 : 0))
            .animation(showsArrival ? .easeOut(duration: 0.2) : .easeIn(duration: 0.9), value: showsArrival)
    }

    private var twoLines: some View {
        VStack(alignment: .leading, spacing: 1) {
            leadLine
            detailLine { secondLine }
        }
    }

    private var oneLine: some View {
        HStack(spacing: 6) {
            leadLine
            secondLine
            metrics
            badges
        }
        // Chosen only at its ideal width, so it must never be squeezed below it.
        // Without this the project-first line truncated "Nuxt" to "N…".
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var leadLine: some View {
        switch effectiveLayout {
        case .serviceFirst: serviceLine
        case .projectFirst: projectLine
        }
    }

    @ViewBuilder
    private var secondLine: some View {
        switch effectiveLayout {
        case .serviceFirst: folderLine
        case .projectFirst: serviceLine
        }
    }

    /// On hover the actions take the pills' place, so they never cover the name,
    /// project or version. Both are always laid out in one slot as wide as the
    /// wider of them, so the text beside it never re-truncates as the pointer
    /// moves across rows.
    private var trailingSlot: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 10) {
                HealthPill(service: service)
                PortPill(port: service.port, extraPorts: service.secondaryPorts)
            }
            .opacity(showsActions ? 0 : 1)

            if showsHoverActions {
                HoverActionsView(service: service, isSharing: $isSharing)
                    .opacity(showsActions ? 1 : 0)
                    .allowsHitTesting(showsActions)
            }
        }
    }

    /// Project-first leads with the project's own icon, which is usually its
    /// favicon, and falls back to the framework logo when there is none.
    private var leadingIcon: some View {
        ServiceIconView(
            type: service.type,
            projectIconPath: effectiveLayout == .projectFirst ? service.project?.iconPath : nil,
            size: Theme.Metrics.rowIcon(compact: state.compactRows)
        )
    }

    private var serviceLine: some View {
        HStack(spacing: 5) {
            if effectiveLayout == .projectFirst {
                ServiceIconView(type: service.type, size: Theme.Metrics.serviceIconSmall)
            }
            Text(service.displayName)
                .font(effectiveLayout == .projectFirst ? .portDetail : .portName)
                .foregroundStyle(effectiveLayout == .projectFirst ? Theme.secondaryText : Theme.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            if let version = service.version {
                TrailingFact(text: version, font: .portVersion)
            }
            if state.isWatched(service) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.tertiaryText)
                    .help("Notifies when it stops")
            }
        }
    }

    /// The badges ride the second line only when the whole line fits. Beside
    /// the name an origin badge left "Cl…" of "Cloudflare Workers", and beside the
    /// folder or a project-first service name it left "N…" of "Nuxt", so a row
    /// too narrow for both drops the badges to a line of their own.
    @ViewBuilder
    private func detailLine(@ViewBuilder _ lead: () -> some View) -> some View {
        if hasBadges {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) { lead(); metrics; badges }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) { lead(); metrics }
                    badges
                }
            }
        } else {
            HStack(spacing: 4) { lead(); metrics }
        }
    }

    private var hasBadges: Bool { service.origin != nil || service.container != nil }

    private var badges: some View {
        HStack(spacing: 4) {
            if let origin = service.origin {
                OriginBadge(origin: origin)
            }
            if service.container != nil {
                TintedBadge(text: ContainerRuntime.displayName(of: service.listenerProcess), tint: Theme.pathDirectory)
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
                TrailingFact(text: "@ \(version)", font: .portVersion, fixed: false)
            }
        }
    }

    // Two labels rather than one string, so the version reads as secondary to the
    // folder in the same way it does beside the service name.
    private var folderLine: some View {
        HStack(spacing: 4) {
            if let subtitle = service.subtitle {
                Text(subtitle)
                    .font(.portDetail)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
            }
            // Gives way to an origin badge. Squeezed beside one, the version
            // shrank to a lone clipped "@", and the heading already names the project.
            if let version = service.project?.version, service.origin == nil {
                TrailingFact(text: "@ \(version)", font: .portVersion, fixed: false)
            }
        }
    }

    /// Uptime and CPU, on the line under the name.
    ///
    /// Uptime is read at scan time, not on a clock. A row only redraws when the
    /// scan behind it moves, so a machine where nothing changes shows an uptime
    /// that ages in jumps. Anything finer would mean redrawing every row every
    /// second, which is the redraw this app is built to avoid, and nobody reads a
    /// three day old dev server to the second.
    /// Nothing for a container row. Both numbers come from the forwarder, so its
    /// uptime is the daemon's and its CPU is every container's at once. A real
    /// container start time needs a second `docker inspect` per container.
    @ViewBuilder
    private var metrics: some View {
        if service.hasHostProcess {
            if state.showsUptime, let started = service.listenerProcess.startTime,
               let uptime = Uptime.duration(since: started) {
                TrailingFact(text: uptime)
            }
            ServiceCPULabel(pid: service.listenerProcess.pid)
        }
    }

    /// The per-service project name, not the group heading. In a sibling group the
    /// heading reads `Wishfox` while each row names its own repository.
    private var projectTitle: String {
        service.project?.name ?? service.displayName
    }

    private var effectiveLayout: ServiceCellLayout {
        service.projectIdentifiesService ? layout : .serviceFirst
    }

    private var isArriving: Bool { state.arrivals.isRecent(service) }

    /// `isArriving` is already true when an arrived row is first built, and SwiftUI
    /// does not animate an initial value, so the row has to render transparent once
    /// and flip afterwards or there is no fade in. `ImageRenderer` never calls
    /// `onAppear`, which is why a snapshot skips the latch.
    private var showsArrival: Bool {
        isArriving && (hasAppeared || SnapshotRenderer.requestedPath != nil)
    }

    private var showsActions: Bool { showsHoverActions && (isHovering || forcedHover || isSharing) }
    private var isHighlighted: Bool { showsActions || (isHovering && !showsHoverActions) }
}

/// A dim fact appended to a line: the version of the thing that is running, or
/// how long it has been up.
struct TrailingFact: View {
    let text: String
    var font: Font = .portCaption
    /// Beside a service name the fact must never shrink, since the name can
    /// truncate instead. Beside a folder it is the fact that gives way.
    var fixed = true

    var body: some View {
        Text(text)
            .font(font)
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
        if service.networkPort != nil {
            Button("Copy LAN Address") { state.copyNetworkAddress(service) }
        }
        if service.revealDirectory != nil {
            Button("Reveal in Finder") { state.reveal(service) }
            if let editor = state.editorApp {
                Button("Open in \(editor.name)") { state.openInEditor(service) }
            }
            if let terminal = state.terminalApp {
                Button("Open in \(terminal.name)") { state.openInTerminal(service) }
            }
        }
        if service.hasHostProcess {
            Divider()
            Button("Stop") { Task { await state.stop(service) } }
            if state.isStubborn(service) {
                Button("Force Stop") { Task { await state.forceStop(service) } }
            }
        }
        // A terminal that cannot be handed a script gets the honest half of the
        // action instead of a Restart that would quietly do nothing.
        if state.relaunchableServiceIDs.contains(service.id) {
            if state.canRestart {
                Button("Restart") { Task { await state.restart(service) } }
            } else {
                Button("Stop and Copy Command") { Task { await state.stopAndCopyCommand(service) } }
            }
        }
        if state.canWatch(service) {
            Divider()
            Button(state.isPinned(service) ? "Unpin" : "Pin to Top") { state.togglePin(service) }
            Toggle("Notify When It Stops", isOn: state.watchBinding(for: service))
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
        if let container = service.container {
            Text("Container \(container.name) · \(container.image)")
        } else {
            Text("PID \(service.listenerProcess.pid) · stops \(service.rootProcess.pid)")
        }
    }
}
