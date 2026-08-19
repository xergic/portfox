import PortFoxKit
import SwiftUI

struct MenuView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    /// Snapshot rendering forces the hover state, which has no pointer to trigger it.
    var forcesHover = false
    /// ImageRenderer lays out in a single pass and never renders scroll content,
    /// so snapshots drop the scroll container and render the list in full.
    var scrolls = true

    /// Measured height of the service list.
    ///
    /// A `MenuBarExtra` window sizes itself to fit its content, and a `ScrollView`
    /// has no intrinsic height to offer, so it collapses to nothing and the
    /// popover shows only its header and footer. Measuring the content and
    /// setting an explicit height is what gives the window something to size to.
    ///
    /// It starts at the maximum rather than zero so the very first layout pass is
    /// already valid. A single-pass renderer never delivers the measurement, and
    /// the live window would otherwise show one empty frame before settling.
    @State private var listHeight: CGFloat = Theme.Metrics.maximumListHeight

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.separator)

            if state.result.services.isEmpty {
                emptyState
            } else {
                list
            }

            Divider().overlay(Theme.separator)
            footer
        }
        .frame(width: Theme.Metrics.popoverWidth)
        .background(Theme.background)
        .environment(\.colorScheme, .dark)
        .onAppear { state.popoverDidAppear() }
        .onDisappear { state.popoverDidDisappear() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(.menuBarFox)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 19, height: 19)
                .foregroundStyle(Theme.accent)

            Text("PortFox")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.primaryText)

            Text(String(state.serviceCount))
                .font(.portCount)
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.pill)
                )

            Spacer()

            IconButton(symbol: "arrow.trianglehead.2.clockwise", help: "Refresh") {
                Task { await state.refresh(.userRequested) }
            }
            .rotationEffect(.degrees(state.isRefreshing ? 360 : 0))
            .animation(
                state.isRefreshing ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default,
                value: state.isRefreshing
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var list: some View {
        if scrolls {
            ScrollView {
                listContent
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
            }
            .frame(height: min(listHeight, Theme.Metrics.maximumListHeight))
            .scrollBounceBehavior(.basedOnSize)
        } else {
            listContent
        }
    }

    private var listContent: some View {
        VStack(alignment: .leading, spacing: 10) {
                if let error = state.lastError {
                    ErrorBanner(message: error)
                }

                ForEach(state.result.groups) { group in
                    ProjectSectionView(group: group, layout: state.cellLayout, forcesHover: forcesHover)
                }

                if !state.result.standalone.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionHeader(title: "INFRASTRUCTURE & DAEMONS")
                        ForEach(state.result.standalone) { service in
                            ServiceRowView(service: service, layout: state.cellLayout, forcedHover: forcesHover)
                        }
                    }
                }

                if !ungrouped.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionHeader(title: "OTHER LISTENERS")
                        ForEach(ungrouped) { service in
                            ServiceRowView(service: service, layout: state.cellLayout)
                        }
                    }
                }
            }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }

    /// Services with a project that the grouper did not place, plus anything the
    /// split missed. Showing them beats silently dropping a running server.
    private var ungrouped: [RunningService] {
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
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
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
        .help("About PortFox")
    }
}

private struct FooterButton: View {
    let symbol: String
    let title: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                Text(title)
            }
            .font(.system(size: 12))
            .foregroundStyle(isHovering ? Theme.primaryText : Theme.secondaryText)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
