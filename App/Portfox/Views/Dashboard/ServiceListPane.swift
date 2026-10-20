import PortfoxKit
import SwiftUI

/// The dashboard sidebar. Reuses the popover's own project sections and service
/// rows, with selection standing in for hover.
struct ServiceListPane: View {
    @Environment(AppState.self) private var state
    /// The result to draw. Not read off `AppState` directly, because the Ignored
    /// chip renders `ignoredResult` through this same pane.
    let result: ScanResult
    @Bindable var dashboard: DashboardState

    var scrolls = true
    var forcesHover = false

    var body: some View {
        VStack(spacing: 0) {
            searchField
            filters
            Divider().overlay(Theme.separator)
            list
            Divider().overlay(Theme.separator)
            footer
        }
    }

    private var searchField: some View {
        SearchField(
            text: $dashboard.search,
            prompt: "Search by port, framework, path",
            isLive: scrolls
        )
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var filters: some View {
        HStack {
            SegmentedControl(
                selection: $dashboard.filter,
                options: availableFilters.map { ($0, $0.displayName) },
                font: .system(size: 12, weight: .medium)
            )
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    /// The system chip only makes sense once noise is being scanned at all, and
    /// the ignored chip only once something ignored is actually running. Entries
    /// whose process is stopped are a Preferences concern. The database chip
    /// matches the standalone bucket, which hiding daemons empties.
    private var availableFilters: [DashboardState.Filter] {
        DashboardState.Filter.allCases.filter { filter in
            switch filter {
            case .system: state.showAllListeners
            case .ignored: state.hasRunningIgnoredServices
            case .database: !state.hidesDaemons
            default: true
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        if scrolls {
            ScrollView { listContent }
                .frame(maxHeight: .infinity)
                .scrollBounceBehavior(.basedOnSize)
        } else {
            listContent
            Spacer(minLength: 0)
        }
    }

    private var listContent: some View {
        // Narrowed once. Each call to `dashboard.filtered` is a full pass.
        let visible = dashboard.filtered(result)
        return ServiceSections(
            result: visible,
            selectedID: dashboard.selection(among: visible.services)?.id,
            showsHoverActions: false,
            onSelect: select,
            forcesHover: forcesHover
        )
    }

    private func select(_ service: RunningService) {
        dashboard.selectedServiceID = service.id
    }

    /// Sockets, not services. The header counts services, and a single service
    /// often holds several listening sockets. `keeping` carries `allSockets`
    /// through untouched, so a narrowed result still counts every listener.
    private var footer: some View {
        Text("\(result.allSockets.count) active listeners")
            .font(.portCaption)
            .foregroundStyle(Theme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 11))
            .foregroundStyle(Theme.danger)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Metrics.controlRadius, style: .continuous)
                    .fill(Theme.danger.opacity(0.12))
            )
    }
}

enum ByteFormat {
    static func short(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
