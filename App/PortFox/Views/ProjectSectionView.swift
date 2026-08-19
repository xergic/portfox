import PortFoxKit
import SwiftUI

struct ProjectSectionView: View {
    @Environment(AppState.self) private var state

    let group: ProjectGroup
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
                projectIconPath: state.iconPath(for: group),
                size: Theme.Metrics.projectIcon
            )
            Text(group.project.name)
                .font(.portProject)
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
                .fixedSize()
            if let version = group.project.version {
                VersionLabel(text: version)
            }
            Text(group.project.displayPath)
                .font(.portSubtitle)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 4)

            // A hover button rather than a context menu: SwiftUI context menus do
            // not open inside a MenuBarExtra window, and a visible affordance is
            // more discoverable than a hidden right-click anyway.
            if isHovering || forcesHover {
                HStack(spacing: 1) {
                    IconButton(symbol: "photo", help: "Change icon") { presentIconPicker() }
                    if state.hasIconOverride(for: group) {
                        IconButton(symbol: "arrow.uturn.backward", help: "Use the default icon") {
                            state.setIcon(nil, for: group)
                        }
                    }
                    IconButton(symbol: "folder", help: "Reveal in Finder") {
                        state.reveal(group.project.root)
                    }
                }
                .fixedSize()
                .padding(.horizontal, 3)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Theme.pill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Theme.border, lineWidth: 1)
                        )
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
                .fill(Theme.card)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .popover(isPresented: $isPickingIcon, arrowEdge: .bottom) {
            IconPickerView(
                group: group,
                assets: assets,
                currentPath: state.iconPath(for: group)
            ) { path in
                state.setIcon(path, for: group)
            }
        }
    }

    private var services: some View {
        VStack(spacing: 0) {
            ForEach(group.services) { service in
                ServiceRowView(service: service, forcedHover: forcesHover)
            }
        }
        .padding(.leading, 14)
    }

    /// Assets are scanned when the menu item is chosen rather than on every
    /// redraw, because the popover reappears every two seconds.
    private func presentIconPicker() {
        assets = state.projectAssets(for: group)
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
