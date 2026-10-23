import PortfoxKit
import SwiftUI

/// A pin with nothing running behind it. Drawn from what the pin captured, and
/// dimmed, because there is nothing to open, reveal or stop.
struct PinPlaceholderRow: View {
    @Environment(AppState.self) private var state

    let pin: Pin
    var showsHoverActions = true
    var forcedHover = false

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            ServiceIconView(type: pin.type, projectIconPath: pin.iconPath)
                .opacity(0.5)

            VStack(alignment: .leading, spacing: 1) {
                Text(state.displayName(of: pin))
                    .font(.portName)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                Text(detail)
                    .font(.portDetail)
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer(minLength: 0)

            ZStack(alignment: .trailing) {
                if let port = pin.port {
                    PortPill(port: port).opacity(showsActions ? 0 : 0.6)
                }
                if showsHoverActions {
                    actions
                        .opacity(showsActions ? 1 : 0)
                        .allowsHitTesting(showsActions)
                }
            }
        }
        .padding(.horizontal, Theme.Metrics.rowPaddingH)
        .padding(.vertical, Theme.Metrics.rowPaddingV)
        .background(CardBackground(fill: isHovering ? Theme.cardHover : .clear, border: Theme.border))
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .contextMenu {
            Button("Unpin") { state.unpin(pin) }
        }
    }

    private var detail: String {
        [pin.detail, "Not running"].compactMap(\.self).joined(separator: " · ")
    }

    private var actions: some View {
        HStack(spacing: 1) {
            IconButton(symbol: "pin.slash", help: "Unpin") { state.unpin(pin) }
        }
        .fixedSize()
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .background(ControlBackground(fill: Theme.cardHover))
    }

    private var showsActions: Bool { isHovering || forcedHover }
}
