import AppKit
import SwiftUI

struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                IconButton(symbol: "xmark", help: "Close") { dismiss() }
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)

            identity

            Divider().overlay(Theme.separator)
            footer
        }
        .frame(width: 360)
        .background(Theme.background)
    }

    private var identity: some View {
        VStack(spacing: 8) {
            AppIconView(size: 64)
                .padding(.bottom, 2)

            Text(AppInfo.name)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.primaryText)

            Text(AppInfo.fullVersionLabel)
                .font(.portSubtitle)
                .foregroundStyle(Theme.secondaryText)

            Text(AppInfo.summary)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.top, 4)

            Text("Made by \(AppInfo.author)")
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiaryText)
                .padding(.top, 6)

            repositoryButton
                .padding(.top, 10)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }

    private var repositoryButton: some View {
        Button {
            NSWorkspace.shared.open(AppInfo.repositoryURL)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                Text("View on GitHub")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Theme.primaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(ControlBackground(fill: Theme.pill))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(AppInfo.repositoryURL.absoluteString)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.primaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(ControlBackground(fill: Theme.pill))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// `NSApplication.shared` rather than `NSApp`, which is nil while the scene builds.
/// Not `NSImage(named: NSImage.applicationIconName)`: under `ImageRenderer` that
/// image washes the whole snapshot out to grey.
struct AppIconView: View {
    private static let image = NSApplication.shared.applicationIconImage

    let size: CGFloat

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image)
                .resizable()
                .frame(width: size, height: size)
        }
    }
}
