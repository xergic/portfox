import SwiftUI

/// The search box shared by the popover and the dashboard sidebar.
struct SearchField: View {
    @Binding var text: String
    let prompt: String
    /// Takes the keyboard as soon as the field appears.
    var focusesOnAppear = false
    /// False under `ImageRenderer`, where a `TextField` is NSTextField-backed and
    /// renders as a placeholder block, so snapshots draw its contents flat.
    var isLive = true

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
            if isLive {
                TextField(prompt, text: $text, prompt: Text(prompt).foregroundStyle(Theme.secondaryText))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.primaryText)
                    .focused($isFocused)
                    .accessibilityLabel(prompt)
                    .onAppear { if focusesOnAppear { isFocused = true } }
                    .onKeyPress(.escape) {
                        guard !text.isEmpty else { return .ignored }
                        text = ""
                        return .handled
                    }
            } else {
                Text(text.isEmpty ? prompt : text)
                    .font(.system(size: 12))
                    .foregroundStyle(text.isEmpty ? Theme.secondaryText : Theme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !text.isEmpty {
                IconButton(symbol: "xmark.circle.fill", help: "Clear") { text = "" }
            }
        }
        .padding(.horizontal, 9)
        .frame(height: Theme.Metrics.searchHeight)
        .background {
            let shape = RoundedRectangle(cornerRadius: Theme.Metrics.controlRadius, style: .continuous)
            shape.fill(Theme.controlFill)
                .overlay(shape.strokeBorder(isFocused ? Theme.accent.opacity(0.65) : Theme.border, lineWidth: isFocused ? 2 : 0.5))
        }
    }
}
