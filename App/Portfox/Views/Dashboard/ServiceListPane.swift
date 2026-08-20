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
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiaryText)
            if scrolls {
                TextField("Search by port, framework, path", text: $dashboard.search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.primaryText)
            } else {
                // A TextField is NSTextField-backed and renders as a placeholder
                // block under ImageRenderer, so snapshots draw its contents flat.
                Text(dashboard.search.isEmpty ? "Search by port, framework, path" : dashboard.search)
                    .font(.system(size: 12))
                    .foregroundStyle(dashboard.search.isEmpty ? Theme.tertiaryText : Theme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !dashboard.search.isEmpty {
                IconButton(symbol: "xmark.circle.fill", help: "Clear") { dashboard.search = "" }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )
        )
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var filters: some View {
        HStack(spacing: 5) {
            ForEach(availableFilters) { filter in
                FilterChip(title: filter.displayName, isSelected: dashboard.filter == filter) {
                    dashboard.filter = filter
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    /// The system chip only makes sense once noise is being scanned at all, and
    /// the ignored chip only once something ignored is actually running. Entries
    /// whose process is stopped are a Preferences concern.
    private var availableFilters: [DashboardState.Filter] {
        DashboardState.Filter.allCases.filter { filter in
            switch filter {
            case .system: state.showAllListeners
            case .ignored: state.hasRunningIgnoredServices
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
        // Narrowed once. Every section below reads off these, because each call to
        // `dashboard.filtered` is a full pass over the services.
        let visible = dashboard.filtered(result)
        let selectedID = dashboard.selection(among: visible.services)?.id

        return VStack(alignment: .leading, spacing: 10) {
            if let error = state.lastError {
                ErrorBanner(message: error)
            }

            ForEach(visible.groups) { group in
                ProjectSectionView(
                    group: group,
                    layout: state.cellLayout,
                    showsHoverActions: false,
                    selectedServiceID: selectedID,
                    onSelect: select,
                    forcesHover: forcesHover
                )
            }

            if !visible.standalone.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(title: "INFRASTRUCTURE & DAEMONS")
                    ForEach(visible.standalone) { service in
                        row(service, selectedID: selectedID)
                    }
                }
            }

            let ungrouped = ungrouped(in: visible)
            if !ungrouped.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(title: "OTHER LISTENERS")
                    ForEach(ungrouped) { service in
                        row(service, selectedID: selectedID)
                    }
                }
            }
        }
        .padding(10)
    }

    private func row(_ service: RunningService, selectedID: String?) -> some View {
        ServiceRowView(
            service: service,
            layout: state.cellLayout,
            showsHoverActions: false,
            isSelected: service.id == selectedID,
            onTap: select,
            forcedHover: forcesHover
        )
    }

    private func select(_ service: RunningService) {
        dashboard.selectedServiceID = service.id
    }

    /// Services the grouper did not place. Showing them beats silently dropping a
    /// running server.
    private func ungrouped(in visible: ScanResult) -> [RunningService] {
        let placed = Set(
            visible.groups.flatMap { $0.services.map(\.id) } + visible.standalone.map(\.id)
        )
        return visible.services.filter { !placed.contains($0.id) }
    }

    /// Sockets, not services. The header counts services, and a single service
    /// often holds several listening sockets. `keeping` carries `allSockets`
    /// through untouched, so a narrowed result still counts every listener.
    private var footer: some View {
        Text("\(result.allSockets.count) active listeners")
            .font(.system(size: 11))
            .foregroundStyle(Theme.tertiaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
    }
}

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Theme.background : Theme.secondaryText)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Theme.accent : (isHovering ? Theme.cardHover : Theme.card))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
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
                RoundedRectangle(cornerRadius: 8, style: .continuous)
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
