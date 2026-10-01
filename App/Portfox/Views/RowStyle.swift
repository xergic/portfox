import SwiftUI

/// The popover draws each row as its own card, the dashboard sidebar keeps flat
/// rows. An environment value rather than a parameter, so the section views and
/// `TrailingFact` pick it up without threading it through every initializer.
enum RowStyle {
    case flat
    case card

    var subtitleFont: Font { self == .card ? .portDetail : .portSubtitle }
    var factFont: Font { self == .card ? .portCaption : .portVersion }

    var horizontalPadding: CGFloat { self == .card ? 12 : 10 }
    var verticalPadding: CGFloat { self == .card ? 9 : 7 }
    var radius: CGFloat { self == .card ? Theme.Metrics.cardRadius : Theme.Metrics.rowRadius }
    var restFill: Color { self == .card ? Theme.card : .clear }
    var restBorder: Color { self == .card ? Theme.separator : .clear }

    var sectionSpacing: CGFloat { self == .card ? 4 : 2 }
    var rowSpacing: CGFloat { self == .card ? 6 : 0 }
    var rowIndent: CGFloat { self == .card ? 0 : 7 }
    /// A card header above cards would read as one more row, so the popover
    /// drops the fill and lets the heading sit on the background.
    var headerFill: Color { self == .card ? .clear : Theme.card }
    var headerHorizontalPadding: CGFloat { self == .card ? 4 : 10 }
    var headerVerticalPadding: CGFloat { self == .card ? 4 : 8 }
    var headerActionsInset: CGFloat { self == .card ? horizontalPadding : 8 }

    var sectionFont: Font { self == .card ? .portSectionLabel : .portSection }
    var sectionColor: Color { self == .card ? Theme.secondaryText : Theme.tertiaryText }
    var sectionKerning: CGFloat { self == .card ? 0 : 0.8 }
    var sectionCase: Text.Case? { self == .card ? nil : .uppercase }
    var sectionInsets: EdgeInsets {
        self == .card
            ? EdgeInsets(top: 6, leading: 4, bottom: 4, trailing: 4)
            : EdgeInsets(top: 8, leading: 12, bottom: 2, trailing: 12)
    }
}

extension EnvironmentValues {
    @Entry var rowStyle: RowStyle = .flat
}
