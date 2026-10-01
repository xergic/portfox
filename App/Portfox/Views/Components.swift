import SwiftUI

/// The app icon, name and a subtitle, then a summary line and trailing buttons.
/// The popover is too narrow to hold the summary beside the name, so it stacks it.
struct AppHeader<Summary: View, Trailing: View>: View {
    let subtitle: String
    var stacksSummary = false
    @ViewBuilder let summary: () -> Summary
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        if stacksSummary {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) { identity; Spacer(); trailing() }
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
        HStack(spacing: 10) {
            AppIconView(size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(AppInfo.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.primaryText)
                Text(subtitle)
                    .font(.portDetail)
                    .foregroundStyle(Theme.secondaryText)
            }
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
                .font(.portDetailStrong)
                .foregroundStyle(Theme.primaryText)
            Text(label)
                .font(.portDetail)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

extension SummaryCount {
    init(count: Int, label: String, dot: Color) {
        self.init(value: String(count), label: label, dot: dot)
    }
}

/// The popover row's resting card: fill, hairline, radius.
struct CardBackground: View {
    var fill: Color = Theme.card
    var border: Color = Theme.separator

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
        shape.fill(fill).overlay(shape.strokeBorder(border, lineWidth: 1))
    }
}

/// Every button, field and pill: one radius, one hairline, a hover fill.
struct ControlBackground: View {
    var fill: Color = Theme.card
    var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Metrics.controlRadius, style: .continuous)
        shape.fill(isHovering ? Theme.cardHover : fill).overlay(shape.strokeBorder(Theme.separator, lineWidth: 1))
    }
}

/// A small sentence-case label washed in its own tint: a process role, the
/// stop target, an HTTP status.
struct TintedBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.portBadge)
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: Theme.Metrics.badgeRadius, style: .continuous).fill(tint.opacity(0.14))
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

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .fixedSize()
            .foregroundStyle(isPrimary ? Theme.onAccent : tint)
            .padding(.horizontal, 11)
            .frame(height: Theme.Metrics.controlHeight)
            .background(ControlBackground(fill: isPrimary ? Theme.accent : Theme.card, isHovering: isHovering && !isPrimary))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// A connected group with the chosen segment filled in the accent.
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
                        .foregroundStyle(option.value == selection ? Theme.onAccent : Theme.secondaryText)
                        .padding(.horizontal, 10)
                        .frame(height: Theme.Metrics.controlHeight - 2 * Self.inset)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Metrics.controlRadius - Self.inset, style: .continuous)
                                .fill(option.value == selection ? Theme.accent : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Self.inset)
        .background(ControlBackground(fill: Theme.pill))
        .opacity(isEnabled ? 1 : 0.4)
        .allowsHitTesting(isEnabled)
    }
}
