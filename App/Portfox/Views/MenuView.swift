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

    var body: some View {
        let ungrouped = ungroupedServices
        VStack(spacing: 0) {
            header(ungrouped: ungrouped)
            Divider().overlay(Theme.separator)

            if state.result.services.isEmpty {
                emptyState
            } else {
                MeasuredScrollView(height: $listHeight, scrolls: scrolls) { listContent(ungrouped: ungrouped) }
            }

            Divider().overlay(Theme.separator)
            footer
        }
        .frame(width: Theme.Metrics.popoverWidth)
        .background(Theme.background)
        .themedSurface(state.appearance.colorScheme)
        .onAppear { state.popoverDidAppear() }
        .onDisappear { state.popoverDidDisappear() }
    }

    private func header(ungrouped: [RunningService]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AppIconView(size: 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text(AppInfo.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.primaryText)
                    Text("Local services")
                        .font(.portDetail)
                        .foregroundStyle(Theme.secondaryText)
                }

                Spacer()

                IconButton(
                    symbol: "arrow.trianglehead.2.clockwise",
                    help: "Refresh",
                    symbolSize: 13,
                    frameSize: 30,
                    filled: true,
                    spins: state.isRefreshing
                ) {
                    Task { await state.refresh(.userRequested) }
                }
            }

            if !state.result.services.isEmpty {
                summary(ungrouped: ungrouped)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    /// Groups, standalone and ungrouped partition `services`, so the dev count
    /// falls out by subtraction instead of another pass over the groups.
    private func summary(ungrouped: [RunningService]) -> some View {
        let result = state.result
        let devServiceCount = result.services.count - result.standalone.count - ungrouped.count
        return HStack(spacing: 14) {
            SummaryCount(count: devServiceCount, label: devServiceCount == 1 ? "dev service" : "dev services", dot: Theme.accent)
            if !state.result.standalone.isEmpty {
                SummaryCount(count: state.result.standalone.count, label: "infrastructure", dot: Theme.pathDirectory)
            }
            if !ungrouped.isEmpty {
                SummaryCount(count: ungrouped.count, label: "other", dot: Theme.tertiaryText)
            }
        }
    }

    private func listContent(ungrouped: [RunningService]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
                if let error = state.lastError {
                    ErrorBanner(message: error)
                }

                ForEach(state.result.groups) { group in
                    ProjectSectionView(group: group, layout: state.cellLayout, forcesHover: forcesHover)
                }

                if !state.result.standalone.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader(title: "Infrastructure & daemons")
                        ForEach(state.result.standalone) { service in
                            ServiceRowView(service: service, layout: state.cellLayout, forcedHover: forcesHover)
                        }
                    }
                }

                if !ungrouped.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader(title: "Other listeners")
                        ForEach(ungrouped) { service in
                            ServiceRowView(service: service, layout: state.cellLayout)
                        }
                    }
                }
            }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .environment(\.rowStyle, .card)
    }

    /// Services with a project that the grouper did not place, plus anything the
    /// split missed. Showing them beats silently dropping a running server.
    private var ungroupedServices: [RunningService] {
        let placed = Set(
            state.result.groups.flatMap { $0.services.map(\.id) } + state.result.standalone.map(\.id)
        )
        return state.result.services.filter { !placed.contains($0.id) }
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

private struct SummaryCount: View {
    let count: Int
    let label: String
    let dot: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(dot).frame(width: 6, height: 6)
            Text(String(count))
                .font(.portDetailStrong)
                .foregroundStyle(Theme.primaryText)
            Text(label)
                .font(.portDetail)
                .foregroundStyle(Theme.secondaryText)
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
