import PortfoxKit
import SwiftUI

/// A name of the user's own for a project, in place of the one read from its
/// manifest or folder. Return saves, and an empty field brings the detected
/// name back.
struct RenameProjectView: View {
    let group: ProjectGroup
    let hasCustomName: Bool
    let onRename: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @FocusState private var isFocused: Bool

    init(group: ProjectGroup, hasCustomName: Bool, onRename: @escaping (String) -> Void) {
        self.group = group
        self.hasCustomName = hasCustomName
        self.onRename = onRename
        _name = State(initialValue: group.project.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rename Project")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
            TextField("Leave empty for the detected name", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .focused($isFocused)
                .onAppear { isFocused = true }
                .onSubmit { save(name) }
            HStack(spacing: 12) {
                if hasCustomName {
                    Button("Use Detected Name") { save("") }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                Button("Save") { save(name) }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .frame(width: 260)
        .background(Theme.background)
    }

    private func save(_ newName: String) {
        onRename(newName)
        dismiss()
    }
}
