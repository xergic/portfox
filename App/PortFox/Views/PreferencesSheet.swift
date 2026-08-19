import PortFoxKit
import SwiftUI

struct PreferencesSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var launchAtLogin = LaunchAtLogin()

    /// `ImageRenderer` lays out in a single pass and never draws scroll content.
    var scrolls = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.separator)
            scrollContent
            Divider().overlay(Theme.separator)
            footer
        }
        .frame(width: 560)
        .background(Theme.background)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
                .fill(Theme.card)
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.primaryText)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text("PortFox Preferences")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.primaryText)
                Text("Configure scanning, refresh and appearance")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }

            Spacer()

            IconButton(symbol: "xmark", help: "Close") { dismiss() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var scrollContent: some View {
        if scrolls {
            ScrollView { sections }
        } else {
            sections
        }
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 16) {
            discoverySection
            appearanceSection
            filteringSection
            generalSection
        }
        .padding(14)
    }

    private var discoverySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("DISCOVERY & REFRESH", symbol: "arrow.trianglehead.2.clockwise")
            PreferencesCard {
                @Bindable var state = state
                PreferenceRow(
                    title: "Automatic refresh loop",
                    subtitle: "Poll listening TCP sockets while a window is open"
                ) {
                    Toggle("", isOn: $state.automaticRefresh)
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                }
                Divider().overlay(Theme.separator)
                PreferenceRow(title: "Polling interval") {
                    SegmentedControl(
                        selection: $state.pollingSeconds,
                        options: AppState.pollingChoices.map { ($0, "\(String($0))s") },
                        isEnabled: state.automaticRefresh
                    )
                }
                .opacity(state.automaticRefresh ? 1 : 0.4)
            }
        }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("APPEARANCE", symbol: "paintbrush")
            PreferencesCard {
                @Bindable var state = state
                PreferenceRow(
                    title: "Service list layout",
                    subtitle: "Lead each row with the service, or with the project it belongs to"
                ) {
                    SegmentedControl(
                        selection: $state.cellLayout,
                        options: ServiceCellLayout.allCases.map { ($0, $0.displayName) }
                    )
                }
            }
        }
    }

    private var filteringSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("PROCESS FILTERING", symbol: "eye")
            PreferencesCard {
                @Bindable var state = state
                PreferenceRow(
                    title: "Show all listeners",
                    subtitle: "Include background system ports such as CUPS or mDNSResponder"
                ) {
                    Toggle("", isOn: $state.showAllListeners)
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                }
                Divider().overlay(Theme.separator)
                PreferenceRow(
                    title: "Group related services by project",
                    subtitle: "Fold sibling repositories under their shared parent directory"
                ) {
                    Toggle("", isOn: $state.groupSiblingRepositories)
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                }
                Divider().overlay(Theme.separator)
                PreferenceRow(
                    title: "Ignored services",
                    subtitle: ignoredSubtitle
                ) {
                    Text(state.ignoredEntries.isEmpty ? "None" : String(state.ignoredEntries.count))
                        .font(.mono(11, .medium))
                        .foregroundStyle(Theme.tertiaryText)
                }
                ForEach(sortedIgnored) { entry in
                    Divider().overlay(Theme.separator)
                    IgnoredServiceRow(entry: entry) { state.stopIgnoring(entry.key) }
                }
            }
        }
    }

    private var ignoredSubtitle: String {
        state.ignoredEntries.isEmpty
            ? "Right-click any service and choose Ignore Service to hide it everywhere"
            : "Hidden from every list, matched by port and project or binary"
    }

    /// By port, because insertion order tells the user nothing.
    private var sortedIgnored: [IgnoredService] {
        state.ignoredEntries.sorted { ($0.port, $0.name) < ($1.port, $1.name) }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("GENERAL", symbol: "gearshape")
            PreferencesCard {
                PreferenceRow(
                    title: "Launch at login",
                    subtitle: "Start PortFox automatically when you log in"
                ) {
                    Toggle("", isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.set($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                }
                if let error = launchAtLogin.lastError {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.danger)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                }
            }
        }
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
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Theme.pill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Theme.border, lineWidth: 1)
                        )
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func sectionLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.8)
        }
        .foregroundStyle(Theme.tertiaryText)
        .padding(.horizontal, 2)
    }
}

/// The stored name and detail, not a live lookup. This row has to read correctly
/// while nothing is running on that port.
private struct IgnoredServiceRow: View {
    let entry: IgnoredService
    let onRemove: () -> Void

    var body: some View {
        PreferenceRow(title: entry.name, subtitle: entry.detail) {
            PortPill(port: entry.port)
        } control: {
            IconButton(symbol: "xmark", help: "Stop ignoring \(entry.name)", action: onRemove)
        }
    }
}

private struct PreferencesCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .background(
                RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
                    .fill(Theme.card)
            )
    }
}

private struct PreferenceRow<Leading: View, Control: View>: View {
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

private struct SegmentedControl<Value: Hashable>: View {
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
                        .foregroundStyle(option.value == selection ? Theme.background : Theme.secondaryText)
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
