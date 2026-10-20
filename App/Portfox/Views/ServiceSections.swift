import PortfoxKit
import SwiftUI

/// Project groups, then infrastructure, agent tools and the rest, in the order
/// `ScanResult.drawingOrder` walks. Shared by the popover and the dashboard
/// sidebar so the two lists can never disagree on what goes where.
struct ServiceSections: View {
    @Environment(AppState.self) private var state

    let result: ScanResult
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

            ForEach(result.groups) { group in
                ProjectSectionView(
                    group: group,
                    layout: state.cellLayout,
                    showsHoverActions: showsHoverActions,
                    selectedServiceID: selectedID,
                    onSelect: onSelect,
                    forcesHover: forcesHover
                )
            }

            section("Infrastructure & daemons", result.standalone)
            section("Agent tools", result.agentTools)
            section("Other listeners", result.ungrouped)
        }
        .padding(12)
    }

    @ViewBuilder
    private func section(_ title: String, _ services: [RunningService]) -> some View {
        if !services.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: title)
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
    }
}
