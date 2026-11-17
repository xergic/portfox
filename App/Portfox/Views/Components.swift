import PortfoxKit
import SwiftUI

/// The app icon and name, then a summary line and trailing buttons.
/// The popover is too narrow to hold the summary beside the name, so it stacks it.
struct AppHeader<Summary: View, Trailing: View>: View {
    var stacksSummary = false
    @ViewBuilder let summary: () -> Summary
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        if stacksSummary {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) { identity; Spacer(); trailing() }
                summary()
            }
        } else {
            HStack(spacing: 10) {
                identity
                Spacer(minLength: 16)
                summary().padding(.trailing, 6)
                trailing()
            }
        }
    }

    private var identity: some View {
        HStack(spacing: 8) {
            AppIconView(size: 22)
            Text(AppInfo.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
        }
    }
}

/// A coloured dot, a bold figure and a label, as in "• 3 infrastructure".
struct SummaryCount: View {
    let value: String
    let label: String
    let dot: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(dot).frame(width: 6, height: 6)
            Text(value)
                .font(.portCaption.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            Text(label)
                .font(.portCaption)
                .foregroundStyle(Theme.secondaryText)
        }
        // A squeezed count wrapped "dev services" onto two lines.
        .fixedSize()
    }
}

extension SummaryCount {
    init(count: Int, label: String, dot: Color) {
        self.init(value: String(count), label: label, dot: dot)
    }
}

/// A contained element on the window surface: a fact table, the process tree.
struct CardBackground: View {
    var fill: Color = Theme.card
    var border: Color = Theme.separator

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
        shape.fill(fill).overlay(shape.strokeBorder(border, lineWidth: 0.5))
    }
}

/// Every bordered control: one radius, one hairline, a hover fill.
struct ControlBackground: View {
    var fill: Color = Theme.card
    var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Metrics.controlRadius, style: .continuous)
        shape.fill(isHovering ? Theme.cardHover : fill).overlay(shape.strokeBorder(Theme.separator, lineWidth: 0.5))
    }
}

/// Who started a service: an agent, or nobody left alive.
struct OriginBadge: View {
    let origin: ServiceOrigin

    var body: some View {
        TintedBadge(text: origin.label, tint: origin == .orphaned ? Theme.warning : Theme.roleBoundary)
    }
}

/// A small uppercase label washed in its own tint: a process role, the
/// stop target, an origin.
struct TintedBadge: View {
    let text: String
    let tint: Color
    /// Off only where a long value beside fixed buttons must give way, such as
    /// the project name in a detail header. Everywhere else a badge is a warning
    /// or a role and must never be cut.
    var fixesSize = true

    var body: some View {
        Text(text)
            .font(.portBadge)
            .lineLimit(1)
            .fixedSize(horizontal: fixesSize, vertical: false)
            .textCase(.uppercase)
            .tracking(0.45)
            .foregroundStyle(tint)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: Theme.Metrics.badgeRadius, style: .continuous).fill(tint.opacity(0.16))
            )
    }
}

/// The dashboard's text buttons. The primary variant is filled with the accent;
/// every other one is the same outlined control, told apart by icon and tint.
struct ActionButton: View {
    let symbol: String
    let label: String
    var isPrimary = false
    var tint: Color = Theme.primaryText
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .fixedSize()
            .foregroundStyle(isPrimary ? Theme.onAccent : tint)
            .padding(.horizontal, 9)
            .frame(height: Theme.Metrics.buttonHeight)
            .background(ControlBackground(fill: isPrimary ? Theme.accent : Theme.card, isHovering: isHovering && !isPrimary))
            .contentShape(Rectangle())
        }
        .buttonStyle(AppControlStyle())
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { isHovering = $0 }
    }
}

/// A connected group with a raised selection, matching macOS segmented controls.
struct SegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    var font: Font = .mono(11, .medium)
    var isEnabled = true

    private static var inset: CGFloat { 2 }

    var body: some View {
        HStack(spacing: Self.inset) {
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(font)
                        .foregroundStyle(option.value == selection ? Theme.primaryText : Theme.secondaryText)
                        .padding(.horizontal, 9)
                        .frame(height: Theme.Metrics.buttonHeight - 2 * Self.inset)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Metrics.controlRadius - Self.inset, style: .continuous)
                                .fill(option.value == selection ? Theme.segmentSelected : Color.clear)
                                .shadow(color: .black.opacity(option.value == selection ? 0.12 : 0), radius: 1, y: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(AppControlStyle())
                .accessibilityAddTraits(option.value == selection ? .isSelected : [])
            }
        }
        .padding(Self.inset)
        .background(ControlBackground(fill: Theme.pill))
        .opacity(isEnabled ? 1 : 0.4)
        .disabled(!isEnabled)
    }
}

extension Shape where Self == RoundedRectangle {
    /// The flat row's hover and selection fill, and anything sized to match it.
    static var row: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.Metrics.rowRadius, style: .continuous) }
}

/// Keeps custom-drawn controls responsive to a press, including keyboard activation.
struct AppControlStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}
