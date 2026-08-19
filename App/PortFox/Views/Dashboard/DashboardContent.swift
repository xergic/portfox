import PortFoxKit
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
                ServiceListPane(dashboard: dashboard, scrolls: scrolls, forcesHover: forcesHover)
                    .frame(width: Theme.Metrics.sidebarWidth)
                Divider().overlay(Theme.separator)
                detail
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let service = dashboard.selection(in: state.result) {
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
            Text(state.result.services.isEmpty ? "No development services running" : "Nothing matches this filter")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Image(.menuBarFox)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(Color(red: 0.98, green: 0.55, blue: 0.24))

            Text("PortFox — Services & Process Inspector")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)

            Spacer(minLength: 16)

            StatusPill(text: "\(state.serviceCount) Active Services")

            if let memory = totalMemory {
                Text(memory)
                    .font(.portSubtitle)
                    .foregroundStyle(Theme.tertiaryText)
            }

            IconButton(
                symbol: "arrow.trianglehead.2.clockwise",
                help: "Refresh",
                symbolSize: Theme.Metrics.dashboardSymbolSize,
                frameSize: Theme.Metrics.dashboardButtonSize
            ) {
                Task { await state.refresh() }
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

    private var totalMemory: String? {
        let bytes = state.result.services.compactMap(\.listenerProcess.residentMemory).reduce(0, +)
        guard bytes > 0 else { return nil }
        return "\(ByteFormat.short(bytes)) RAM"
    }
}
