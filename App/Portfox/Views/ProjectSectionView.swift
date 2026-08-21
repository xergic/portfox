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
        VStack(alignment: .leading, spacing: 2) {
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
                .font(.portSubtitle)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .truncationMode(.head)
                .padding(.trailing, showsHoverActions ? Theme.Metrics.projectActionsWidth : 0)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
                .fill(Theme.card)
        )
        // An overlay rather than another element in the stack. Inserting the
        // buttons on hover would re-truncate the path and shift the row under
        // the pointer, which reads as the row jumping.
        .overlay(alignment: .trailing) {
            if showsHoverActions, showsActions {
                actions.padding(.trailing, 8)
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
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.cardHover)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )
        )
    }

    private var services: some View {
        VStack(spacing: 0) {
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
        .padding(.leading, 7)
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
            .font(.portSection)
            .kerning(0.8)
            .foregroundStyle(Theme.tertiaryText)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }
}
