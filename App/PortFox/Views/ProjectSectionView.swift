import PortFoxKit
import SwiftUI

struct ProjectSectionView: View {
    let group: ProjectGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 9) {
                ServiceIconView(
                    type: group.services.first?.type ?? .unknown,
                    projectIconPath: group.project.iconPath,
                    size: Theme.Metrics.projectIcon
                )
                Text(group.project.name)
                    .font(.portProject)
                    .foregroundStyle(Theme.primaryText)
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

            VStack(spacing: 0) {
                ForEach(group.services) { service in
                    ServiceRowView(service: service)
                }
            }
            .padding(.leading, 14)
        }
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
