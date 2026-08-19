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
            }
        }
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

private struct PreferenceRow<Control: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer(minLength: 12)
            control()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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
