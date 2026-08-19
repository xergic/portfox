import PortFoxKit
import SwiftUI

struct ProjectSectionView: View {
    @Environment(AppState.self) private var state

    let group: ProjectGroup
    /// Snapshot rendering has no pointer, so it forces the hover state.
    var forcesHover = false

    @State private var isPickingIcon = false
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
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
                .fill(Theme.card)
        )
        .contentShape(Rectangle())
        .contextMenu {
            Button("Change Icon…") { presentIconPicker() }
            if state.hasIconOverride(for: group) {
                Button("Reset Icon") { state.setIcon(nil, for: group) }
            }
            Divider()
            Button("Reveal in Finder") { state.reveal(group.project.root) }
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
