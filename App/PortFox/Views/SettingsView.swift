import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        Form {
            Section("Discovery") {
                Toggle("Show all listeners", isOn: $state.showAllListeners)
                Text("Includes system daemons and background agents. Useful for diagnosing a port conflict.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Grouping") {
                Toggle("Group sibling repositories", isOn: $state.groupSiblingRepositories)
                Text("Separate repositories inside one folder appear under that folder's name.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }
}
