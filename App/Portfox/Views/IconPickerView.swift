import AppKit
import PortfoxKit
import SwiftUI

/// Grid of images already present in a project, so the user can pick which one
/// represents it. Anything outside the project is reachable through Choose File.
struct IconPickerView: View {
    let group: ProjectGroup
    let assets: [ProjectAsset]
    let currentPath: String?
    let onPick: (String?) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 48, maximum: 48), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if assets.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(assets) { asset in
                            AssetCell(asset: asset, isSelected: asset.path == currentPath) {
                                onPick(asset.path)
                                dismiss()
                            }
                        }
                    }
                    .padding(12)
                }
                .frame(height: gridHeight)
            }

            Divider().overlay(Theme.separator)
            footer
        }
        .frame(width: 296)
        .background(Theme.background)
        .environment(\.colorScheme, .dark)
    }

    private var gridHeight: CGFloat {
        let rows = ceil(Double(assets.count) / 5)
        return min(max(CGFloat(rows) * 56 + 16, 72), 232)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Icon for \(group.project.name)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
            Text("\(assets.count) image\(assets.count == 1 ? "" : "s") found in the project")
                .font(.system(size: 10))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var emptyState: some View {
        Text("No images found in this project.")
            .font(.system(size: 11))
            .foregroundStyle(Theme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Choose File…") {
                if let picked = chooseFile() {
                    onPick(picked)
                    dismiss()
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(Theme.secondaryText)

            Spacer()

            if currentPath != nil {
                Button("Use Default") {
                    onPick(nil)
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func chooseFile() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.directoryURL = group.project.root
        panel.prompt = "Use Icon"

        NSApp.activate()
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}

private struct AssetCell: View {
    let asset: ProjectAsset
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if let image = ServiceIconView.loadImage(at: asset.path) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(6)
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            .frame(width: 48, height: 48)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovering ? Theme.cardHover : Theme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isSelected ? Theme.accent : Theme.border, lineWidth: isSelected ? 1.5 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(asset.relativePath)
    }
}
