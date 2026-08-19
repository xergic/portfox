import SwiftUI

struct PortPill: View {
    let port: Int

    var body: some View {
        HStack(spacing: 3) {
            Text(":")
                .foregroundStyle(Theme.tertiaryText)
            Text("\(port)")
                .foregroundStyle(Theme.primaryText)
                .monospacedDigit()
        }
        .font(.portPort)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.pill)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )
        )
    }
}

/// Small square icon button used in the hover action row and the header.
struct IconButton: View {
    let symbol: String
    var tint: Color = Theme.secondaryText
    var help: String = ""
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isHovering ? Theme.primaryText : tint)
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
    }
}
