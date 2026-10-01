import SwiftUI

/// A titled group of facts in the detail pane, wearing the same card fill,
/// hairline and radius as a popover row.
struct DetailCard<Content: View>: View {
    let title: String
    var systemImage: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            titleView
            contentBox
        }
    }

    private var titleView: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(Theme.tertiaryText)
            }
            Text(title)
                .foregroundStyle(Theme.secondaryText)
        }
        .font(.portDetailStrong)
        .padding(.leading, 2)
    }

    private var contentBox: some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CardBackground())
    }
}

/// One label/value fact inside a `DetailCard`. Pass `badge` instead of `value`
/// for a tinted trailing value such as an HTTP response code.
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
    /// Monospace by default, since most values are paths, pids and numbers.
    var valueFont: Font = .portSubtitle
    var valueColor: Color = Theme.primaryText
    var badge: TintedBadge?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            // A fixed column, so the inline values of one card start in line.
            Text(label)
                .font(.portDetail)
                .foregroundStyle(Theme.secondaryText)
                .frame(width: layout == .inline ? Theme.Metrics.factLabelWidth : nil, alignment: .leading)
            if layout == .spread { Spacer(minLength: 0) }
            trailingContent
            if layout == .inline { Spacer(minLength: 0) }
        }
    }

    @ViewBuilder
    private var trailingContent: some View {
        if let badge {
            badge
        } else if let value {
            // Truncating the middle keeps both the volume root and the file
            // name in view, which is what actually identifies a long path.
            Text(value)
                .font(valueFont)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .truncationMode(.middle)
        } else {
            Text("Unknown")
                .font(.portDetail)
                .foregroundStyle(Theme.tertiaryText)
        }
    }
}

/// A `Divider` styled to match the rest of the dashboard's hairlines.
struct CardDivider: View {
    var body: some View {
        Divider().overlay(Theme.separator)
    }
}
