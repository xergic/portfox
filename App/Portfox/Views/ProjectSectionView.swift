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
    @State private var isRenaming = false
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
                .groupLabelStyle()
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
                // On the name rather than on the hover actions, which vanish the
                // moment the pointer moves into the popover and would take it along.
                .popover(isPresented: $isRenaming, arrowEdge: .bottom) {
                    RenameProjectView(group: group, hasCustomName: state.customName(of: group) != nil) { name in
                        state.rename(group, to: name)
                    }
                }
            if state.isPinned(group) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.tertiaryText)
                    .help("Pinned to the top")
            }
            Spacer(minLength: 8)
            Text(group.project.displayPath)
                .font(.portSubtitle)
                .foregroundStyle(Theme.tertiaryText)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(minWidth: Theme.Metrics.pathMinWidth, alignment: .trailing)
                .opacity(showsHoverActions && showsActions ? 0 : 1)
        }
        .padding(Theme.Metrics.groupHeaderInsets)
        // An overlay rather than another element in the stack. Inserting the
        // buttons on hover would re-truncate the path and shift the row under
        // the pointer, which reads as the row jumping.
        .overlay(alignment: .trailing) {
            if showsHoverActions, showsActions {
                // On the surface colour, so a long name running under the buttons
                // is covered rather than drawn through them.
                actions
                    .padding(.leading, 6)
                    .background(Theme.background)
                    .padding(.trailing, Theme.Metrics.headerActionsInset)
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
            IconButton(
                symbol: state.isPinned(group) ? "pin.slash" : "pin",
                help: state.isPinned(group) ? "Unpin" : "Pin to top"
            ) { state.togglePin(group) }
            IconButton(symbol: "pencil", help: "Rename") { isRenaming = true }
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
    }

    private var services: some View {
        RowList(group.services) { service in
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
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).groupLabelStyle()
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.portCaption)
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .lineLimit(1)
        .padding(Theme.Metrics.groupHeaderInsets)
    }
}
