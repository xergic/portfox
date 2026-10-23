import PortfoxKit
import SwiftUI

struct MenuView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    /// Snapshot rendering forces the hover state, which has no pointer to trigger it.
    var forcesHover = false
    /// ImageRenderer lays out in a single pass and never renders scroll content,
    /// so snapshots drop the scroll container and render the list in full.
    var scrolls = true

    @State private var listHeight: CGFloat = Theme.Metrics.maximumListHeight
    @State private var query = ""
    /// Moved by the arrow keys. Nil until one is pressed, so a fresh query
    /// highlights its first match rather than whatever was picked before.
    @State private var keyboardSelectionID: String?

    var body: some View {
        // A stopped pin cannot match a query, it has no service to search.
        let sections = state.sections(of: state.result.matching(query), showsStoppedPins: query.isEmpty)
        let ordered = sections.drawingOrder
        let selectedID = selection(in: ordered)?.id
        VStack(spacing: 0) {
            header(ungrouped: state.result.ungrouped)
            Divider().overlay(Theme.separator)

            if state.result.services.isEmpty, sections.stoppedPins.isEmpty {
                emptyState
            } else {
                searchField
                if sections.isEmpty {
                    noMatches
                } else {
                    ScrollViewReader { proxy in
                        MeasuredScrollView(height: $listHeight, scrolls: scrolls) {
                            ServiceSections(sections: sections, selectedID: selectedID, forcesHover: forcesHover)
                        }
                        .onChange(of: selectedID) {
                            guard let selectedID else { return }
                            proxy.scrollTo(selectedID)
                        }
                    }
                }
            }

            Divider().overlay(Theme.separator)
            footer
        }
        .frame(width: Theme.Metrics.popoverWidth)
        .background(Theme.background)
        .themedSurface(state.appearance.colorScheme)
        // On the root rather than the field, so the keys still work after a
        // click lands on a row and the field loses focus.
        .onKeyPress { press in handle(press, in: ordered) }
        .onAppear { state.popoverDidAppear() }
        .onDisappear {
            query = ""
            state.popoverDidDisappear()
        }
        .onChange(of: query) { keyboardSelectionID = nil }
    }

    private var searchField: some View {
        SearchField(
            text: $query,
            prompt: "Search ports, projects, commands",
            focusesOnAppear: true,
            isLive: scrolls
        )
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    private func handle(_ press: KeyPress, in ordered: [RunningService]) -> KeyPress.Result {
        switch press.key {
        case .downArrow:
            return moveSelection(by: 1, in: ordered)
        case .upArrow:
            return moveSelection(by: -1, in: ordered)
        case .return:
            guard let service = selection(in: ordered), service.localURL != nil else { return .ignored }
            state.open(service)
            return .handled
        case .delete where press.modifiers.contains(.command):
            guard let service = selection(in: ordered), service.hasHostProcess else { return .ignored }
            Task { await state.stop(service) }
            return .handled
        default:
            return .ignored
        }
    }

    /// The row Return and Cmd-Delete act on. A typed query always has one, so
    /// "5173, Return" opens it without touching the arrows.
    private func selection(in ordered: [RunningService]) -> RunningService? {
        if let keyboardSelectionID, let match = ordered.first(where: { $0.id == keyboardSelectionID }) {
            return match
        }
        return query.isEmpty ? nil : ordered.first
    }

    private func moveSelection(by step: Int, in ordered: [RunningService]) -> KeyPress.Result {
        guard !ordered.isEmpty else { return .ignored }
        let current = selection(in: ordered).flatMap { selected in ordered.firstIndex { $0.id == selected.id } }
        let next = current.map { ($0 + step + ordered.count) % ordered.count } ?? (step > 0 ? 0 : ordered.count - 1)
        keyboardSelectionID = ordered[next].id
        return .handled
    }

    private func header(ungrouped: [RunningService]) -> some View {
        AppHeader(subtitle: "Local services", stacksSummary: true) {
            if !state.result.services.isEmpty {
                summary(ungrouped: ungrouped)
            }
        } trailing: {
            IconButton(
                symbol: "arrow.trianglehead.2.clockwise",
                help: "Refresh",
                symbolSize: Theme.Metrics.headerSymbolSize,
                frameSize: Theme.Metrics.headerButtonSize,
                filled: true,
                spins: state.isRefreshing
            ) {
                Task { await state.refresh(.userRequested) }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    /// Groups, standalone, agent tools and ungrouped partition `services`, so the dev count
    /// falls out by subtraction instead of another pass over the groups.
    private func summary(ungrouped: [RunningService]) -> some View {
        let result = state.result
        let devServiceCount = result.services.count - result.standalone.count - result.agentTools.count - ungrouped.count
        return HStack(spacing: 10) {
            if devServiceCount > 0 {
                SummaryCount(count: devServiceCount, label: devServiceCount == 1 ? "dev service" : "dev services", dot: Theme.accent)
            }
            if !result.standalone.isEmpty {
                SummaryCount(count: result.standalone.count, label: "infrastructure", dot: Theme.pathDirectory)
            }
            if !result.agentTools.isEmpty {
                let count = result.agentTools.count
                SummaryCount(count: count, label: count == 1 ? "agent tool" : "agent tools", dot: Theme.roleBoundary)
            }
            if !ungrouped.isEmpty {
                SummaryCount(count: ungrouped.count, label: "other", dot: Theme.tertiaryText)
            }
            let orphanedCount = result.services.count { $0.origin == .orphaned }
            if orphanedCount > 0 {
                SummaryCount(count: orphanedCount, label: "orphaned", dot: Theme.warning)
            }
        }
    }

    private var noMatches: some View {
        Text("No services match \u{201C}\(query)\u{201D}")
            .font(.system(size: 12))
            .foregroundStyle(Theme.secondaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 22))
                .foregroundStyle(Theme.tertiaryText)
            // "Nothing running" would be a lie when the user hid it all, and it
            // reads as a broken scanner rather than a filter doing its job.
            Text(state.emptyStateMessage)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
            if let error = state.lastError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.danger)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            FooterButton(symbol: "macwindow", title: "Dashboard") {
                WindowPresenter.showDashboard(openWindow)
            }

            FooterButton(symbol: "slider.horizontal.3", title: "Settings…") {
                // Set before the window opens, so the sheet is already requested on
                // its first layout pass rather than a runloop turn too late.
                state.presentedSheet = .preferences
                WindowPresenter.showDashboard(openWindow)
            }

            // Two services is where the button earns its width. With one, Stop
            // All is the row's own Stop with a longer name.
            if state.stoppableServices.count > 1 {
                StopAllButton()
            }

            Spacer()

            VersionButton {
                state.presentedSheet = .about
                WindowPresenter.showDashboard(openWindow)
            }

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// Arms on the first press and fires on the second.
///
/// A modal alert would be the usual confirmation, but a `MenuBarExtra` popover
/// closes the moment focus leaves it, so the question would arrive after the
/// list it is asking about had gone. Arming happens in place and disarms as soon
/// as the pointer leaves.
private struct StopAllButton: View {
    @Environment(AppState.self) private var state

    @State private var isArmed = false

    var body: some View {
        FooterButton(
            symbol: isArmed ? "exclamationmark.triangle.fill" : "stop.circle",
            // The count is what will actually stop, not what is listed, so the
            // question cannot promise more than the button delivers.
            title: isArmed ? "Stop \(state.stoppableServices.count)?" : "Stop All",
            tint: isArmed ? Theme.danger : nil
        ) {
            guard isArmed else {
                isArmed = true
                return
            }
            isArmed = false
            Task { await state.stopAllVisible() }
        }
        .onHover { hovering in
            if !hovering { isArmed = false }
        }
    }
}

private struct VersionButton: View {
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(AppInfo.versionLabel)
                .font(.portVersion)
                .foregroundStyle(isHovering ? Theme.secondaryText : Theme.tertiaryText)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("About Portfox")
    }
}

private struct FooterButton: View {
    let symbol: String
    let title: String
    /// Overrides the hover colouring, for a button that has to look dangerous
    /// whether or not the pointer is on it.
    var tint: Color?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                Text(title)
            }
            .font(.system(size: 12))
            .foregroundStyle(tint ?? (isHovering ? Theme.primaryText : Theme.secondaryText))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
