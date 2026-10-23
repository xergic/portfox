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
        VStack(alignment: .leading, spacing: 12) {
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
        .padding(12)
    }

    private var pinnedRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Pinned")
            rows(sections.pinnedServices)
            ForEach(sections.stoppedPins) { pin in
                PinPlaceholderRow(pin: pin, showsHoverActions: showsHoverActions, forcedHover: forcesHover)
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
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: title)
                rows(services)
            }
        }
    }

    private func rows(_ services: [RunningService]) -> some View {
        ForEach(services) { service in
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
}
