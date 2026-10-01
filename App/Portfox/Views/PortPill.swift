import SwiftUI

struct PortPill: View {
    let port: Int

    var body: some View {
        HStack(spacing: 3) {
            Text(":")
                .foregroundStyle(Theme.tertiaryText)
            // A port is an identifier, not a quantity. Locale grouping renders
            // 3111 as "3 111".
            Text(String(port))
                .foregroundStyle(Theme.primaryText)
        }
        .font(.portPort)
        .lineLimit(1)
        .fixedSize()
        .frame(width: Theme.Metrics.portPillWidth, height: 21)
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
    var symbolSize: CGFloat = 11
    var frameSize: CGFloat = 20
    /// A round-rect fill behind the glyph, for a button that stands alone in a header.
    var filled = false
    /// Spins the glyph only, so a filled button's background stays put.
    var spins = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: symbolSize, weight: .medium))
                .foregroundStyle(isHovering ? Theme.primaryText : tint)
                .rotationEffect(.degrees(spins ? 360 : 0))
                .animation(
                    spins ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default,
                    value: spins
                )
                .frame(width: frameSize, height: frameSize)
                .background {
                    if filled {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isHovering ? Theme.cardHover : Theme.card)
                            .strokeBorder(Theme.separator, lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
    }
}
