import PortfoxKit
import SwiftUI

/// Everything the dashboard draws. Deliberately free of `NavigationSplitView`,
/// `List`, `.toolbar` and `.searchable`, all of which need a hosting window and
/// render blank under `ImageRenderer`.
struct DashboardContent: View {
    @Environment(AppState.self) private var state
    @Bindable var dashboard: DashboardState

    /// `ImageRenderer` lays out in a single pass and never draws scroll content.
    var scrolls = true
    var forcesHover = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().overlay(Theme.separator)

            HStack(spacing: 0) {
                ServiceListPane(result: source, dashboard: dashboard, scrolls: scrolls, forcesHover: forcesHover)
                    .frame(width: Theme.Metrics.sidebarWidth)
                Divider().overlay(Theme.separator)
                detail
            }
        }
        // The chip is hidden once nothing ignored is running, so leaving the
        // filter selected would strand the sidebar on a filter it cannot show.
        // Watches the same condition the chip does, not the stored entry count,
        // which stays non-empty after the last ignored service exits.
        .onChange(of: state.hasRunningIgnoredServices) { _, hasAny in
            if !hasAny, dashboard.filter == .ignored { dashboard.filter = .all }
        }
        // Same reason, for the chip that hiding daemons removes.
        .onChange(of: state.hidesDaemons) { _, hides in
            if hides, dashboard.filter == .database { dashboard.filter = .all }
        }
    }

    /// The Ignored chip renders a different result, not a different view.
    private var source: ScanResult {
        dashboard.filter == .ignored ? state.ignoredResult : state.result
    }

    @ViewBuilder
    private var detail: some View {
        if let service = dashboard.selection(in: source) {
            ServiceDetailPane(service: service, dashboard: dashboard, scrolls: scrolls)
        } else {
            emptyDetail
        }
    }

    private var emptyDetail: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 28))
                .foregroundStyle(Theme.tertiaryText)
            Text(emptyDetailMessage)
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyDetailMessage: String {
        guard source.services.isEmpty else { return "Nothing matches this filter" }
        guard dashboard.filter != .ignored else {
            return "No ignored service is running. Manage the full list in Preferences."
        }
        return state.emptyStateMessage
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Image(.menuBarFox)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(Theme.accent)

            Text("Portfox — Services & Process Inspector")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)

            Spacer(minLength: 16)

            StatusPill(text: "\(state.serviceCount) Active Services")

            WatchedMemoryLabel()

            IconButton(
                symbol: "arrow.trianglehead.2.clockwise",
                help: "Refresh",
                symbolSize: Theme.Metrics.dashboardSymbolSize,
                frameSize: Theme.Metrics.dashboardButtonSize
            ) {
                Task { await state.refresh(.userRequested) }
            }
            .rotationEffect(.degrees(state.isRefreshing ? 360 : 0))
            .animation(
                state.isRefreshing ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default,
                value: state.isRefreshing
            )

            IconButton(
                symbol: "slider.horizontal.3",
                help: "Preferences",
                symbolSize: Theme.Metrics.dashboardSymbolSize,
                frameSize: Theme.Metrics.dashboardButtonSize
            ) {
                state.presentedSheet = .preferences
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
    }

}
