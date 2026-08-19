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
            switch dashboard.tab {
            case .services:
                ServiceDetailPane(service: service, dashboard: dashboard, scrolls: scrolls)
            case .processTree:
                ProcessTreePane(service: service, scrolls: scrolls)
            }
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

            Text("PortFox")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.primaryText)

            Spacer(minLength: 16)
            tabs
            Spacer(minLength: 16)

            IconButton(symbol: "arrow.trianglehead.2.clockwise", help: "Refresh") {
                Task { await state.refresh() }
            }
            .rotationEffect(.degrees(state.isRefreshing ? 360 : 0))
            .animation(
                state.isRefreshing ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default,
                value: state.isRefreshing
            )

            IconButton(symbol: "slider.horizontal.3", help: "Preferences") {
                state.presentedSheet = .preferences
            }
        }
        // Leading inset clears the traffic lights, which sit inside this bar.
        .padding(.leading, 78)
        .padding(.trailing, 14)
        .frame(height: 52)
    }

    private var tabs: some View {
        HStack(spacing: 2) {
            ForEach(DashboardState.Tab.allCases, id: \.self) { tab in
                TabButton(
                    title: tab == .services ? "Services (\(state.serviceCount))" : tab.displayName,
                    isSelected: dashboard.tab == tab
                ) {
                    dashboard.tab = tab
                }
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.pill)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )
        )
        .fixedSize()
    }
}

private struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Theme.primaryText : Theme.secondaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(background)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var background: Color {
        if isSelected { return Theme.cardHover }
        return isHovering ? Theme.card : .clear
    }
}
