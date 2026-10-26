import PortfoxKit
import SwiftUI

/// Pinned rows, then project groups with the pinned ones first, infrastructure, agent tools and the rest,
/// in the order `ListSections.drawingOrder` walks. Shared by the popover and
/// the dashboard sidebar so the two lists can never disagree on what goes where.
struct ServiceSections: View {
    @Environment(AppState.self) private var state

    let sections: ListSections
    var selectedID: String?
    var showsHoverActions = true
    /// Nil opens the service in a browser, which is what the popover wants.
    var onSelect: ((RunningService) -> Void)?
    var forcesHover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = state.lastError {
                ErrorBanner(message: error)
            }

            if sections.hasPinnedRows {
                pinnedRows
            }

            ForEach(sections.pinnedGroups + sections.rest.groups) { group in
                projectSection(group)
            }

            section("Infrastructure & daemons", sections.rest.standalone)
            section("Agent tools", sections.rest.agentTools)
            section("Other listeners", sections.rest.ungrouped)
        }
        .padding(.horizontal, Theme.Metrics.listInset)
        .padding(.vertical, 6)
    }

    private var pinnedRows: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionHeader(title: "Pinned")
            RowList(sections.pinnedServices.map(PinnedRow.running) + sections.stoppedPins.map(PinnedRow.stopped)) { row in
                switch row {
                case .running(let service): serviceRow(service)
                case .stopped(let pin):
                    PinPlaceholderRow(pin: pin, showsHoverActions: showsHoverActions, forcedHover: forcesHover)
                }
            }
        }
    }

    private func projectSection(_ group: ProjectGroup) -> some View {
        ProjectSectionView(
            group: group,
            layout: state.cellLayout,
            showsHoverActions: showsHoverActions,
            selectedServiceID: selectedID,
            onSelect: onSelect,
            forcesHover: forcesHover
        )
    }

    @ViewBuilder
    private func section(_ title: String, _ services: [RunningService]) -> some View {
        if !services.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                SectionHeader(title: title, trailing: services.count == 1 ? "1 service" : "\(services.count) services")
                RowList(services) { serviceRow($0) }
            }
        }
    }

    private func serviceRow(_ service: RunningService) -> some View {
        ServiceRowView(
            service: service,
            layout: state.cellLayout,
            showsHoverActions: showsHoverActions,
            isSelected: service.id == selectedID,
            onTap: onSelect,
            forcedHover: forcesHover
        )
    }
}

private enum PinnedRow: Identifiable {
    case running(RunningService)
    case stopped(Pin)

    /// The bare service id, so the popover's arrow keys can still scroll to it.
    var id: AnyHashable {
        switch self {
        case .running(let service): service.id
        case .stopped(let pin): pin.id
        }
    }
}

/// Rows flat on the surface with a hairline between neighbours, never above the
/// first. A row draws no card of its own, so this is the only thing that tells
/// two rows apart at rest.
struct RowList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    @ViewBuilder let row: (Item) -> Row

    init(_ items: [Item], @ViewBuilder row: @escaping (Item) -> Row) {
        self.items = items
        self.row = row
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                if item.id != items.first?.id {
                    Rectangle()
                        .fill(Theme.separator)
                        .frame(height: 1)
                        .padding(.horizontal, Theme.Metrics.listRowPaddingH)
                }
                row(item)
            }
        }
    }
}
