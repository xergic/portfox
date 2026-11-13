import SwiftUI

/// Banners about dev servers that need a look, not about anything starting.
struct WarningPreferences: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        @Bindable var limits = state.memoryAlerts
        PreferencesSection(title: "Resource alerts") {
            PreferenceRow(title: "Warn about memory use", subtitle: memorySubtitle) {
                PreferenceCheckbox(isOn: $state.warnsAboutMemory)
            }
            PreferenceDivider()
            limitRow("One server", selection: $limits.perServiceGB, choices: MemoryAlerts.perServiceChoices)
            PreferenceDivider()
            limitRow("All servers", selection: $limits.totalGB, choices: MemoryAlerts.totalChoices)
            PreferenceDivider()
            PreferenceRow(title: "Warn about idle agent servers", subtitle: idleSubtitle) {
                PreferenceCheckbox(isOn: $state.warnsAboutIdleServers)
            }
        }
    }

    private func limitRow(_ title: String, selection: Binding<Int>, choices: [Int]) -> some View {
        PreferenceRow(title: title) {
            SegmentedControl(
                selection: selection,
                options: choices.map { ($0, "\($0) GB") },
                isEnabled: state.warnsAboutMemory
            )
        }
        .opacity(state.warnsAboutMemory ? 1 : 0.4)
    }

    private var memorySubtitle: String {
        blocker(isOn: state.warnsAboutMemory)
            ?? "One banner when a dev server, or all of them together, passes a limit. Databases are left out."
    }

    private var idleSubtitle: String {
        blocker(isOn: state.warnsAboutIdleServers)
            ?? "One banner with a Stop button when a server Claude Code or Codex started has been idle for an hour"
    }

    /// Says why a checked box stays quiet, rather than letting it look broken.
    private func blocker(isOn: Bool) -> String? {
        guard isOn else { return nil }
        if !state.notifier.isAuthorized { return "Needs notifications, which macOS has not allowed for Portfox." }
        if !state.automaticRefresh {
            return "Automatic refresh is off. Nothing is measured in the background."
        }
        return nil
    }
}
