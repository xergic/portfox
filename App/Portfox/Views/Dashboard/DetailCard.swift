import SwiftUI

/// Bordered card chrome for a labelled group of facts in a detail pane, styled
/// after `SectionHeader` and `ProjectSectionView`'s card background.
struct DetailCard<Content: View>: View {
    let title: String
    var systemImage: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            titleView
            contentBox
        }
    }

    private var titleView: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(title.uppercased())
                .kerning(0.8)
        }
        .font(.portSection)
        .foregroundStyle(Theme.tertiaryText)
    }

    private var contentBox: some View {
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
                    .fill(Theme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
                            .strokeBorder(Theme.border, lineWidth: 1)
                    )
            )
    }
}

/// One label/value fact inside a `DetailCard`. Pass `badge` instead of `value`
/// for a status-pill trailing value such as an HTTP response code.
struct LabeledRow: View {
    /// `spread` pushes the value to the trailing edge, which lines up a column of
    /// short values. `inline` keeps it beside its label, which reads better for
    /// long paths that would otherwise truncate against a distant label.
    enum Layout {
        case spread
        case inline
    }

    let label: String
    let value: String?
    var layout: Layout = .spread
    var valueFont: Font = .portSubtitle
    var valueColor: Color = Theme.primaryText
    var isMonospaced = true
    var badge: StatusPill?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: layout == .inline ? 6 : 0) {
            Text(layout == .inline ? "\(label):" : label)
                .font(labelFont)
                .foregroundStyle(Theme.secondaryText)
            if layout == .spread { Spacer(minLength: 12) }
            trailingContent
            if layout == .inline { Spacer(minLength: 0) }
        }
    }

    private var labelFont: Font {
        layout == .inline ? .portSubtitle : .system(size: 11)
    }

    private var effectiveFont: Font { isMonospaced ? valueFont.monospaced() : valueFont }

    @ViewBuilder
    private var trailingContent: some View {
        if let badge {
            badge
        } else if let value {
            // Truncating the middle keeps both the volume root and the file
            // name in view, which is what actually identifies a long path.
            Text(value)
                .font(effectiveFont)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .truncationMode(.middle)
        } else {
            Text("Unknown")
                .font(valueFont)
                .foregroundStyle(Theme.tertiaryText)
        }
    }
}

/// Small badge-style value, for example an HTTP status pill on a `LabeledRow`.
/// A tint colours both the fill and the text; without one it matches `PortPill`.
struct StatusPill: View {
    let text: String
    var tint: Color?

    var body: some View {
        Text(text)
            .font(.mono(11, .medium))
            .foregroundStyle(tint ?? Theme.primaryText)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tint?.opacity(0.15) ?? Theme.pill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(tint?.opacity(0.35) ?? Theme.border, lineWidth: 1)
                    )
            )
    }
}

/// A `Divider` styled to match the rest of the dashboard's hairlines.
struct CardDivider: View {
    var body: some View {
        Divider().overlay(Theme.separator)
    }
}
