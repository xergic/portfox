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
            case .preferences: "Portfox preferences"
            case .ignored: "Ignored services"
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
                IconButton(
                symbol: "chevron.left",
                help: "Back to preferences",
                frameSize: Theme.Metrics.headerButtonSize,
                filled: true
            ) { page = .preferences }
            }

            RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
                .fill(Theme.accent)
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: page.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.onAccent)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(page.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.primaryText)
                Text(page.subtitle)
                    .font(.portDetail)
                    .foregroundStyle(Theme.secondaryText)
            }

            Spacer()

            IconButton(
                symbol: "xmark",
                help: "Close",
                frameSize: Theme.Metrics.headerButtonSize,
                filled: true
            ) { dismiss() }
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
        PreferencesSection(title: "Discovery and refresh", symbol: "arrow.trianglehead.2.clockwise") {
            @Bindable var state = state
            PreferenceRow(
                title: "Automatic refresh loop",
                subtitle: "Poll listening TCP sockets while a window is open"
            ) {
                PreferenceCheckbox(isOn: $state.automaticRefresh)
            }
            PreferenceDivider()
            PreferenceRow(title: "Polling interval") {
                SegmentedControl(
                    selection: $state.pollingSeconds,
                    options: AppState.pollingChoices.map { ($0, "\(String($0))s") },
                    isEnabled: state.automaticRefresh
                )
            }
            .opacity(state.automaticRefresh ? 1 : 0.4)
            PreferenceDivider()
            arrivalNotificationRow
        }
    }

    /// Enabled whichever way the loop is set, matching the CPU toggle. Turning it
    /// on now so it works when the loop comes back is a reasonable thing to want,
    /// and only the polling control is genuinely inert without the loop.
    private var arrivalNotificationRow: some View {
        @Bindable var notifier = state.arrivals.notifier
        return VStack(spacing: 0) {
            PreferenceRow(title: "Notify when a service appears", subtitle: arrivalSubtitle) {
                PreferenceCheckbox(isOn: $notifier.isEnabled)
            }
            if let error = state.arrivals.notifier.lastError {
                Text(error)
                    .font(.portCaption)
                    .foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Metrics.rowPaddingH)
                    .padding(.bottom, 10)
            }
        }
    }

    /// Nothing is scanned in the background with the loop off, so an arrival is
    /// only noticed the next time a window opens.
    private var arrivalSubtitle: String {
        state.automaticRefresh
            ? "A banner when something starts listening. Ignored and system ports are left out."
            : "Needs the automatic refresh loop, which is off. Nothing is scanned in the background."
    }

    private var appearanceSection: some View {
        PreferencesSection(title: "Appearance", symbol: "paintbrush") {
            @Bindable var state = state
            @Bindable var appearance = state.appearance
            PreferenceRow(
                title: "Theme",
                subtitle: "Follow the system theme, or pin Portfox to light or dark"
            ) {
                SegmentedControl(
                    selection: $appearance.preference,
                    options: AppAppearance.allCases.map { ($0, $0.displayName) },
                    font: .system(size: 11, weight: .medium)
                )
            }
            PreferenceDivider()
            PreferenceRow(
                title: "Show count in menu bar",
                subtitle: "Draw the number of active services next to the icon"
            ) {
                PreferenceCheckbox(isOn: $state.showsMenuBarCount)
            }
            PreferenceDivider()
            PreferenceRow(
                title: "Service list layout",
                subtitle: "Lead each row with the service, or with the project it belongs to"
            ) {
                SegmentedControl(
                    selection: $state.cellLayout,
                    options: ServiceCellLayout.allCases.map { ($0, $0.displayName) },
                    font: .system(size: 11, weight: .medium)
                )
            }
            PreferenceDivider()
            PreferenceRow(
                title: "Show uptime",
                subtitle: "How long each service has been running, beside its folder"
            ) {
                PreferenceCheckbox(isOn: $state.showsUptime)
            }
            PreferenceDivider()
            PreferenceRow(
                title: "Show CPU usage",
                subtitle: cpuSubtitle
            ) {
                PreferenceCheckbox(isOn: $state.showsCPU)
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
        PreferencesSection(title: "Applications", symbol: "square.grid.2x2") {
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
            PreferenceDivider()
            PreferenceRow(title: "Terminal", subtitle: terminalSubtitle) {
                AppMenu(
                    apps: ExternalApps.terminals,
                    selection: $state.terminalBundleID,
                    fallback: "None found"
                )
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
        PreferencesSection(title: "Process filtering", symbol: "eye") {
            @Bindable var state = state
            PreferenceRow(
                title: "Show all listeners",
                subtitle: "Include background system ports such as CUPS or mDNSResponder"
            ) {
                PreferenceCheckbox(isOn: $state.showAllListeners)
            }
            PreferenceDivider()
            PreferenceRow(
                title: "Hide infrastructure and daemons",
                subtitle: "Leave out databases, daemons and anything without a project, and drop them from the counts"
            ) {
                PreferenceCheckbox(isOn: $state.hidesDaemons)
            }
            PreferenceDivider()
            PreferenceRow(
                title: "Group related services by project",
                subtitle: "Fold sibling repositories under their shared parent directory"
            ) {
                PreferenceCheckbox(isOn: $state.groupSiblingRepositories)
            }
            PreferenceDivider()
            DisclosureRow(
                title: "Ignored services",
                subtitle: ignoredSubtitle,
                value: state.ignoredEntries.isEmpty ? nil : String(state.ignoredEntries.count)
            ) {
                page = .ignored
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
                    .font(.portSectionLabel)
                    .foregroundStyle(Theme.secondaryText)
                Text(Self.ignoreHint)
                    .font(.portCaption)
                    .foregroundStyle(Theme.tertiaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            PreferencesCard {
                ForEach(Array(sortedIgnored.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        PreferenceDivider()
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
        PreferencesSection(title: "General", symbol: "gearshape") {
            PreferenceRow(
                title: "Launch at login",
                subtitle: "Start Portfox automatically when you log in"
            ) {
                PreferenceCheckbox(isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.set($0) }
                ))
            }
            if let error = launchAtLogin.lastError {
                Text(error)
                    .font(.portCaption)
                    .foregroundStyle(Theme.danger)
                    .padding(.horizontal, Theme.Metrics.rowPaddingH)
                    .padding(.bottom, 10)
            }
            PreferenceDivider()
            @Bindable var state = state
            PreferenceRow(
                title: "Share anonymous usage data",
                subtitle: "Never includes project names, paths or ports"
            ) {
                PreferenceCheckbox(isOn: $state.sharesUsageData)
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            ActionButton(
                symbol: page == .ignored ? "chevron.left" : "checkmark",
                label: page == .ignored ? "Back" : "Done",
                isPrimary: true
            ) {
                if page == .ignored { page = .preferences } else { dismiss() }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// A settings row that opens a screen of its own, showing what is behind it.
private struct DisclosureRow: View {
    let title: String
    let subtitle: String
    let value: String?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            PreferenceRow(title: title, subtitle: subtitle) {
                HStack(spacing: 6) {
                    Text(value ?? "None")
                        .font(value == nil ? .portCaption : .portVersion)
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
