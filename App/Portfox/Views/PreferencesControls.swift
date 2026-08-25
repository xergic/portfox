import PortfoxKit
import SwiftUI

/// The shared chrome the preferences sheet is built from.
///
/// In its own file, because `PreferencesSheet` had grown past what one file
/// should hold. Nothing here knows a preference, only how a row looks.

struct PreferencesCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .background(
                RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
                    .fill(Theme.card)
            )
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
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 12)
            control()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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
                .font(.mono(11))
                .foregroundStyle(Theme.tertiaryText)
        } else {
            Menu {
                ForEach(apps) { app in
                    Button(app.name) { selection = app.bundleID }
                }
            } label: {
                Text(currentName)
                    .font(.mono(11, .medium))
                    .foregroundStyle(Theme.secondaryText)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.pill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Theme.border, lineWidth: 1)
                    )
            )
        }
    }

    /// Resolved the same way the actions resolve it, so the row cannot claim one
    /// app while Open in… launches another.
    private var currentName: String {
        ExternalApps.resolve(selection, among: apps)?.name ?? fallback
    }
}

struct SegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    var isEnabled = true

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(.mono(11, .medium))
                        .foregroundStyle(option.value == selection ? Theme.onAccent : Theme.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(option.value == selection ? Theme.accent : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.pill)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )
        )
        .opacity(isEnabled ? 1 : 0.4)
        .allowsHitTesting(isEnabled)
    }
}
