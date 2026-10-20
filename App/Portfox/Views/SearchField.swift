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
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.tertiaryText)
            if isLive {
                TextField(prompt, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.primaryText)
                    .focused($isFocused)
                    .onAppear { if focusesOnAppear { isFocused = true } }
                    .onKeyPress(.escape) {
                        guard !text.isEmpty else { return .ignored }
                        text = ""
                        return .handled
                    }
            } else {
                Text(text.isEmpty ? prompt : text)
                    .font(.system(size: 13))
                    .foregroundStyle(text.isEmpty ? Theme.tertiaryText : Theme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !text.isEmpty {
                IconButton(symbol: "xmark.circle.fill", help: "Clear") { text = "" }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: Theme.Metrics.controlHeight)
        .background(ControlBackground(fill: Theme.pill))
    }
}
