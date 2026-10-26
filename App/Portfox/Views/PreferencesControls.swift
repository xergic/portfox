import PortfoxKit
import SwiftUI

/// The shared chrome the preferences sheet is built from.
///
/// In its own file, because `PreferencesSheet` had grown past what one file
/// should hold. Nothing here knows a preference, only how a row looks.

struct PreferencesCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    /// Clipped, so a row's square hover fill follows the card's rounded corners
    /// and the hairline is drawn over it rather than under.
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 0, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.separator, lineWidth: 1))
    }
}

/// A titled group of rows in a card, the preferences twin of `DetailCard`.
struct PreferencesSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .groupLabelStyle()
                .padding(.leading, 2)
            PreferencesCard(content: content)
        }
    }
}

struct PreferenceDivider: View {
    var body: some View {
        Divider().overlay(Theme.separator)
    }
}

struct PreferenceCheckbox: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .tint(Theme.accent)
    }
}

struct PreferenceRow<Leading: View, Control: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            leading()
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(.portCaption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control()
        }
        .padding(.horizontal, Theme.Metrics.rowPaddingH)
        .padding(.vertical, Theme.Metrics.listRowPaddingV)
    }
}

extension PreferenceRow where Leading == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder control: @escaping () -> Control) {
        self.init(title: title, subtitle: subtitle, leading: { EmptyView() }, control: control)
    }
}

/// A dropdown of installed apps.
///
/// Like every AppKit-backed control in this sheet it renders as a placeholder
/// block under `ImageRenderer`, so a snapshot shows where the choice sits but
/// never which app is chosen.
struct AppMenu: View {
    let apps: [ExternalApp]
    @Binding var selection: String?
    let fallback: String

    var body: some View {
        if apps.isEmpty {
            Text(fallback)
                .font(.portCaption)
                .foregroundStyle(Theme.tertiaryText)
        } else {
            Menu {
                ForEach(apps) { app in
                    Button(app.name) { selection = app.bundleID }
                }
            } label: {
                Text(currentName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 8)
            .frame(height: Theme.Metrics.buttonHeight)
            .background(ControlBackground(fill: Theme.pill))
        }
    }

    /// Resolved the same way the actions resolve it, so the row cannot claim one
    /// app while Open in… launches another.
    private var currentName: String {
        ExternalApps.resolve(selection, among: apps)?.name ?? fallback
    }
}
