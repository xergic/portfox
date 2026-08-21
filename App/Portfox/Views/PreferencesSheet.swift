import PortfoxKit
import SwiftUI

struct PreferencesSheet: View {
    /// The sheet is two screens, not one page. An ignore list grows without
    /// bound, and every hidden service would otherwise push the settings the user
    /// came for further down.
    enum Page {
        case preferences
        case ignored

        var symbol: String {
            switch self {
            case .preferences: "slider.horizontal.3"
            case .ignored: "eye.slash"
            }
        }

        var title: String {
            switch self {
            case .preferences: "Portfox Preferences"
            case .ignored: "Ignored Services"
            }
        }

        var subtitle: String {
            switch self {
            case .preferences: "Configure scanning, refresh and appearance"
            case .ignored: "Hidden from every list, matched by port and project or binary"
            }
        }
    }

    /// How a service gets onto the ignore list, shown wherever the list is empty.
    private static let ignoreHint = "Right-click any service and choose Ignore Service to hide it everywhere"

    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var launchAtLogin = LaunchAtLogin()
    @State private var page: Page

    @State private var ignoredHeight: CGFloat = Theme.Metrics.maximumListHeight

    /// `ImageRenderer` lays out in a single pass and never draws scroll content.
    var scrolls = true

    init(page: Page = .preferences, scrolls: Bool = true) {
        _page = State(initialValue: page)
        self.scrolls = scrolls
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.separator)
            switch page {
            case .preferences: scrollContent
            case .ignored: ignoredContent
            }
            Divider().overlay(Theme.separator)
            footer
        }
        .frame(width: 560)
        .background(Theme.background)
        .themedSurface(state.appearance.colorScheme)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if page == .ignored {
                IconButton(symbol: "chevron.left", help: "Back to Preferences") { page = .preferences }
            }

            RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
                .fill(Theme.card)
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: page.symbol)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.primaryText)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(page.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.primaryText)
                Text(page.subtitle)
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
            applicationsSection
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
                @Bindable var appearance = state.appearance
                PreferenceRow(
                    title: "Appearance",
                    subtitle: "Follow the system theme, or pin Portfox to light or dark"
                ) {
                    SegmentedControl(
                        selection: $appearance.preference,
                        options: AppAppearance.allCases.map { ($0, $0.displayName) }
                    )
                }
                Divider().overlay(Theme.separator)
                PreferenceRow(
                    title: "Show count in menu bar",
                    subtitle: "Draw the number of active services next to the icon"
                ) {
                    Toggle("", isOn: $state.showsMenuBarCount)
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                }
                Divider().overlay(Theme.separator)
                PreferenceRow(
                    title: "Service list layout",
                    subtitle: "Lead each row with the service, or with the project it belongs to"
                ) {
                    SegmentedControl(
                        selection: $state.cellLayout,
                        options: ServiceCellLayout.allCases.map { ($0, $0.displayName) }
                    )
                }
                Divider().overlay(Theme.separator)
                PreferenceRow(
                    title: "Show uptime",
                    subtitle: "How long each service has been running, beside its folder"
                ) {
                    Toggle("", isOn: $state.showsUptime)
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                }
                Divider().overlay(Theme.separator)
                PreferenceRow(
                    title: "Show CPU usage",
                    subtitle: cpuSubtitle
                ) {
                    Toggle("", isOn: $state.showsCPU)
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                }
            }
        }
    }

    /// CPU is a rate measured between two ticks. With the loop off there is never
    /// a second tick, so the row would sit empty and the toggle would look broken.
    private var cpuSubtitle: String {
        state.automaticRefresh
            ? "Percent of one core, listener and workers together, as Activity Monitor counts it"
            : "Needs the automatic refresh loop, which is off. It is measured between two scans."
    }

    private var applicationsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("APPLICATIONS", symbol: "square.grid.2x2")
            PreferencesCard {
                @Bindable var state = state
                PreferenceRow(
                    title: "Editor",
                    subtitle: "Open in… opens the service's repository"
                ) {
                    AppMenu(
                        apps: ExternalApps.editors,
                        selection: $state.editorBundleID,
                        fallback: "None found"
                    )
                }
                Divider().overlay(Theme.separator)
                PreferenceRow(title: "Terminal", subtitle: terminalSubtitle) {
                    AppMenu(
                        apps: ExternalApps.terminals,
                        selection: $state.terminalBundleID,
                        fallback: "None found"
                    )
                }
            }
        }
    }

    private var terminalSubtitle: String {
        guard let terminal = state.terminalApp else {
            return "Opens a window in the directory the service runs in"
        }
        if state.canRestart {
            return "Opens a window in the directory the service runs in, and runs Restart"
        }
        return "Opens a window in the directory the service runs in. \(terminal.name) "
            + "cannot be asked to run a command, so Restart becomes Stop and Copy Command."
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
                    title: "Hide infrastructure and daemons",
                    subtitle: "Leave out databases, daemons and anything without a project, and drop them from the counts"
                ) {
                    Toggle("", isOn: $state.hidesDaemons)
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
                DisclosureRow(
                    title: "Ignored services",
                    subtitle: ignoredSubtitle,
                    value: state.ignoredEntries.isEmpty ? "None" : String(state.ignoredEntries.count)
                ) {
                    page = .ignored
                }
            }
        }
    }

    // MARK: - Ignored services screen

    private var ignoredContent: some View {
        MeasuredScrollView(height: $ignoredHeight, scrolls: scrolls) { ignoredList }
    }

    @ViewBuilder
    private var ignoredList: some View {
        if state.ignoredEntries.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "eye")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.tertiaryText)
                Text("Nothing is ignored")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                Text(Self.ignoreHint)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            PreferencesCard {
                ForEach(Array(sortedIgnored.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        Divider().overlay(Theme.separator)
                    }
                    IgnoredServiceRow(entry: entry) { state.stopIgnoring(entry.key) }
                }
            }
            .padding(14)
        }
    }

    private var ignoredSubtitle: String {
        state.ignoredEntries.isEmpty ? Self.ignoreHint : Page.ignored.subtitle
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
                    subtitle: "Start Portfox automatically when you log in"
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
            Button(page == .ignored ? "Back" : "Done") {
                if page == .ignored { page = .preferences } else { dismiss() }
            }
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

/// A settings row that opens a screen of its own, showing what is behind it.
private struct DisclosureRow: View {
    let title: String
    let subtitle: String
    let value: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            PreferenceRow(title: title, subtitle: subtitle) {
                HStack(spacing: 6) {
                    Text(value)
                        .font(.mono(11, .medium))
                        .foregroundStyle(Theme.tertiaryText)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isHovering ? Theme.primaryText : Theme.tertiaryText)
                }
            }
            .background(isHovering ? Theme.cardHover : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
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

/// A dropdown of installed apps.
///
/// Like every AppKit-backed control in this sheet it renders as a placeholder
/// block under `ImageRenderer`, so a snapshot shows where the choice sits but
/// never which app is chosen.
private struct AppMenu: View {
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
