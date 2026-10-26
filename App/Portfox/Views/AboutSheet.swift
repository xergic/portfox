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
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.primaryText)

            Text(AppInfo.fullVersionLabel)
                .font(.portVersion)
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

            if Updater.shared.isAvailable {
                updateButton
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }

    private var repositoryButton: some View {
        PillButton(symbol: "arrow.up.right", label: "View on GitHub") {
            NSWorkspace.shared.open(AppInfo.repositoryURL)
        }
        .help(AppInfo.repositoryURL.absoluteString)
    }

    private var updateButton: some View {
        PillButton(symbol: "arrow.down.circle", label: "Check for Updates…") {
            Updater.shared.checkForUpdates()
        }
        .disabled(!Updater.shared.canCheckForUpdates)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.primaryText)
                .padding(.horizontal, 10)
                .frame(height: Theme.Metrics.buttonHeight)
                .background(ControlBackground(fill: Theme.pill))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct PillButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Theme.primaryText)
            .padding(.horizontal, 10)
            .frame(height: Theme.Metrics.buttonHeight)
            .background(ControlBackground(fill: Theme.pill))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
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
