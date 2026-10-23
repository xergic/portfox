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
                HStack(spacing: 8) {
                    if isWaiting {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.accentText)
                            .help("Notifies when it is up")
                    }
                    if let port = pin.port {
                        PortPill(port: port).opacity(0.6)
                    }
                }
                .opacity(showsActions ? 0 : 1)
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
            Button(isWaiting ? "Stop Waiting" : "Notify When It Is Up", action: toggleWait)
            Button("Unpin") { state.unpin(pin) }
        }
    }

    private var detail: String {
        [pin.detail, isWaiting ? "Waiting for it to start" : "Not running"].compactMap(\.self).joined(separator: " · ")
    }

    private var isWaiting: Bool { state.isWaiting(for: state.waitTarget(of: pin)) }

    private func toggleWait() {
        state.toggleWait(for: state.waitTarget(of: pin), label: state.displayName(of: pin))
    }

    private var actions: some View {
        HStack(spacing: 1) {
            IconButton(
                symbol: isWaiting ? "bell.slash" : "bell",
                help: isWaiting ? "Stop waiting" : "Notify when it is up",
                action: toggleWait
            )
            IconButton(symbol: "pin.slash", help: "Unpin") { state.unpin(pin) }
        }
        .fixedSize()
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .background(ControlBackground(fill: Theme.cardHover))
    }

    private var showsActions: Bool { isHovering || forcedHover }
}
