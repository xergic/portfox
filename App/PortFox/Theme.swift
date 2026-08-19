import SwiftUI

/// The popover is always dark, matching the design, so colours are literal
/// rather than semantic. A light appearance is out of scope for the MVP.
enum Theme {
    static let background = Color(red: 0.055, green: 0.055, blue: 0.063)
    static let card = Color(red: 0.106, green: 0.106, blue: 0.118)
    static let cardHover = Color(red: 0.137, green: 0.137, blue: 0.153)
    static let separator = Color.white.opacity(0.07)
    static let border = Color.white.opacity(0.09)

    static let primaryText = Color(red: 0.949, green: 0.949, blue: 0.957)
    static let secondaryText = Color(red: 0.541, green: 0.541, blue: 0.576)
    static let tertiaryText = Color(red: 0.396, green: 0.396, blue: 0.427)

    static let accent = Color(red: 0.133, green: 0.773, blue: 0.369)
    static let danger = Color(red: 0.937, green: 0.267, blue: 0.267)

    static let pill = Color(red: 0.137, green: 0.137, blue: 0.149)

    enum Metrics {
        static let popoverWidth: CGFloat = 404
        static let maximumListHeight: CGFloat = 460
        static let cardRadius: CGFloat = 10
        static let rowRadius: CGFloat = 9
        static let serviceIcon: CGFloat = 22
        /// Fixed so four and five digit ports align, and so the hover actions can
        /// be positioned beside the pill without measuring it.
        static let portPillWidth: CGFloat = 66
        /// Space the hover actions occupy. Reserved even at rest, so revealing
        /// them never re-truncates the text or shifts the row under the pointer.
        static let rowActionsWidth: CGFloat = 72
        static let projectIcon: CGFloat = 22
    }
}

extension Font {
    /// JetBrains Mono, bundled under the SIL Open Font License. Chosen over the
    /// system monospace for its wider, more even digits, which is most of what
    /// this UI shows. The NL cut has no ligatures, so a path never renders an
    /// arrow where it should show two characters.
    static func mono(_ size: CGFloat, _ weight: MonoWeight = .regular) -> Font {
        .custom(weight.postScriptName, size: size)
    }

    enum MonoWeight {
        case regular
        case medium
        case semibold

        var postScriptName: String {
            switch self {
            case .regular: "JetBrainsMonoNL-Regular"
            case .medium: "JetBrainsMonoNL-Medium"
            case .semibold: "JetBrainsMonoNL-SemiBold"
            }
        }
    }

    static let portName = Font.system(size: 13, weight: .semibold)
    static let portProject = Font.system(size: 13, weight: .bold)
    static let portSubtitle = Font.mono(11)
    static let portPort = Font.mono(12, .medium)
    static let portVersion = Font.mono(10)
    static let portSection = Font.system(size: 10, weight: .semibold)
    static let portCount = Font.mono(11, .medium)
}
