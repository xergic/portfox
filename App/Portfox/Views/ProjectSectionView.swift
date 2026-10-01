import PortfoxKit
import SwiftUI

struct ProjectSectionView: View {
    @Environment(AppState.self) private var state

    let group: ProjectGroup
    var layout: ServiceCellLayout = .serviceFirst
    var showsHoverActions = true
    var selectedServiceID: String?
    var onSelect: ((RunningService) -> Void)?
    /// Snapshot rendering has no pointer, so it forces the hover state.
    var forcesHover = false

    @State private var isPickingIcon = false
    @State private var isHovering = false
    @State private var assets: [ProjectAsset] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            services
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            ServiceIconView(
                type: group.services.first?.type ?? .unknown,
                projectIconPath: state.projectIcons.iconPath(for: group),
                size: Theme.Metrics.projectIcon
            )
            Text(group.project.name)
                .font(.portProject)
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
                .fixedSize()
            Text(group.project.displayPath)
                .font(.portDetail)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .truncationMode(.head)
                .padding(.trailing, showsHoverActions ? Theme.Metrics.projectActionsWidth : 0)
            Spacer(minLength: 0)
        }
        // Bare on the background, because a card header above cards would read
        // as one more row.
        .padding(4)
        // An overlay rather than another element in the stack. Inserting the
        // buttons on hover would re-truncate the path and shift the row under
        // the pointer, which reads as the row jumping.
        .overlay(alignment: .trailing) {
            if showsHoverActions, showsActions {
                actions.padding(.trailing, 12)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .popover(isPresented: $isPickingIcon, arrowEdge: .bottom) {
            IconPickerView(
                group: group,
                assets: assets,
                currentPath: state.projectIcons.iconPath(for: group)
            ) { path in
                state.projectIcons.setIcon(path, for: group)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 1) {
            IconButton(symbol: "photo", help: "Change icon") { presentIconPicker() }
            if state.projectIcons.hasIconOverride(for: group) {
                IconButton(symbol: "arrow.uturn.backward", help: "Use the default icon") {
                    state.projectIcons.setIcon(nil, for: group)
                }
            }
            IconButton(symbol: "folder", help: "Reveal in Finder") { state.reveal(group.project.root) }
            IconButton(symbol: "stop.fill", tint: Theme.danger, help: "Stop every service in this project") {
                Task { await state.stopAll(in: group) }
            }
        }
        .fixedSize()
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .background(ControlBackground(fill: Theme.cardHover))
    }

    private var services: some View {
        VStack(spacing: 6) {
            ForEach(group.services) { service in
                ServiceRowView(
                    service: service,
                    layout: layout,
                    showsHoverActions: showsHoverActions,
                    isSelected: service.id == selectedServiceID,
                    onTap: onSelect,
                    forcedHover: forcesHover
                )
            }
        }
    }

    private var showsActions: Bool { isHovering || forcesHover }

    /// Assets are scanned when the menu item is chosen rather than on every
    /// redraw, because the popover reappears every two seconds.
    private func presentIconPicker() {
        assets = state.projectIcons.projectAssets(for: group)
        isPickingIcon = true
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.portSectionLabel)
            .foregroundStyle(Theme.secondaryText)
            .padding(EdgeInsets(top: 6, leading: 4, bottom: 4, trailing: 4))
    }
}
