import AppKit
import SwiftUI

/// Two literal palettes rather than semantic system colours, because the design
/// is a specific dark grey and a specific off-white, not whatever the OS picks.
///
/// Every token is a dynamic `NSColor`, so it resolves against the `\.colorScheme`
/// of the surface being drawn. That is what makes a light appearance reach ~200
/// unchanged call sites, and it keeps working under `ImageRenderer`, where a
/// snapshot of the light appearance has to actually come out light.
enum Theme {
    /// Rows sit straight on this, so it is the row colour as well as the window's.
    static let background = dynamic(dark: srgb(0.110, 0.110, 0.118), light: srgb(1, 1, 1))
    /// One step up from `background`: a contained element such as a fact table.
    static let card = dynamic(dark: srgb(0.165, 0.165, 0.176), light: srgb(0.957, 0.957, 0.965))
    static let cardHover = dynamic(dark: srgb(0.180, 0.180, 0.192), light: srgb(0.929, 0.929, 0.941))
    static let separator = dynamic(dark: srgb(1, 1, 1, 0.07), light: srgb(0, 0, 0, 0.08))
    static let border = dynamic(dark: srgb(1, 1, 1, 0.10), light: srgb(0, 0, 0, 0.12))

    static let primaryText = dynamic(dark: srgb(0.949, 0.949, 0.957), light: srgb(0.106, 0.106, 0.118))
    static let secondaryText = dynamic(dark: srgb(0.541, 0.541, 0.576), light: srgb(0.400, 0.400, 0.435))
    static let tertiaryText = dynamic(dark: srgb(0.396, 0.396, 0.427), light: srgb(0.557, 0.557, 0.588))

    /// Interactive chrome only: a primary button, a selected row, a chosen
    /// segment. The same teal as the app icon, so the accent is the brand.
    /// One value for both appearances, because a brand that changes shade with
    /// the theme stops being a brand.
    static let accent = Color(nsColor: accentBrand)
    /// The accent as text or a glyph rather than a fill. Brand teal on white is
    /// 2.1:1, so light darkens it; dark keeps the brand value exactly.
    static let accentText = dynamic(dark: accentBrand, light: srgb(0.0, 0.478, 0.427))
    /// Ink for text sitting on an accent fill. Near-black in both appearances:
    /// black scores 10:1 on the teal where white scores 2.1:1. Not
    /// `background`, which used to stand in for it and inverts in light.
    static let onAccent = Color(nsColor: ink)

    /// "This is healthy", never chrome. A warmer green than the teal accent,
    /// so a 200 OK does not read as a selected control.
    static let success = dynamic(dark: successDark, light: successLight)
    static let danger = dynamic(dark: srgb(0.937, 0.267, 0.267), light: srgb(0.784, 0.110, 0.110))

    static let pill = dynamic(dark: srgb(0.165, 0.165, 0.176), light: srgb(0.941, 0.941, 0.953))

    /// What a process is doing in a service's tree, matching `ProcessRole`.
    static let roleBoundary = dynamic(dark: srgb(0.694, 0.549, 0.973), light: srgb(0.486, 0.227, 0.929))
    static let roleWrapper = dynamic(dark: srgb(0.965, 0.694, 0.290), light: srgb(0.706, 0.325, 0.035))
    static let roleService = success
    /// A process nothing will stop on its own. Yellower than `roleWrapper`, so
    /// an orphan never reads as a process role.
    static let warning = dynamic(dark: srgb(0.984, 0.749, 0.141), light: srgb(0.631, 0.384, 0.027))

    /// The listening process's row in the tree, a wash of `roleService` over the
    /// card. Alpha over near-black and alpha over white do not read the same: 6%
    /// separates the row in dark and is invisible in light, so light gets more.
    static let listenerRow = dynamic(
        dark: successDark.withAlphaComponent(0.06),
        light: successLight.withAlphaComponent(0.10)
    )
    static let listenerBorder = dynamic(
        dark: successDark.withAlphaComponent(0.45),
        light: successLight.withAlphaComponent(0.55)
    )

    /// Opaque, the accent mixed into `background`, so a selected row needs no
    /// second layer under it.
    static let selectedRow = dynamic(dark: srgb(0.097, 0.191, 0.193), light: srgb(0.860, 0.970, 0.964))

    /// A row that appeared since the previous scan, washed for a few seconds.
    /// Same asymmetry as `listenerRow` and for the same measured reason: alpha
    /// over near-black and alpha over white do not read the same, so light gets
    /// more. Much stronger than `listenerRow`, because the fill is the whole
    /// effect: the arrival carries no border, so nothing else marks the row, and
    /// it still has to stay legible over `cardHover` when the pointer is on it.
    static let arrivalRow = dynamic(
        dark: successDark.withAlphaComponent(0.26),
        light: successLight.withAlphaComponent(0.28)
    )

    /// Path values in the metadata card, so the executable and the working
    /// directory are told apart without reading their labels.
    static let pathExecutable = roleWrapper
    static let pathDirectory = dynamic(dark: srgb(0.376, 0.647, 0.980), light: srgb(0.146, 0.388, 0.922))

    private static let accentBrand = srgb(0.0, 0.786, 0.741)
    private static let ink = srgb(0.055, 0.055, 0.063)
    private static let successDark = srgb(0.133, 0.773, 0.369)
    private static let successLight = srgb(0.016, 0.471, 0.341)

    /// Resolved at draw time, never at read time, so a token can stay a
    /// `static let` and SwiftUI still repaints it when the appearance moves.
    private static func dynamic(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    private static func srgb(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) -> NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    enum Metrics {
        static let popoverWidth: CGFloat = 404
        static let maximumListHeight: CGFloat = 460
        static let cardRadius: CGFloat = 10
        /// The hover and selection fill of a flat row.
        static let rowRadius: CGFloat = 6
        static let searchHeight: CGFloat = 26
        /// Bordered controls: action buttons and the segmented filter.
        static let controlRadius: CGFloat = 8
        static let buttonHeight: CGFloat = 24
        static let badgeRadius: CGFloat = 3
        static let rowPaddingH: CGFloat = 12
        /// A flat list row. Narrower than `rowPaddingH`, so the row's text lines
        /// up with the header while its hover fill still has room to show.
        static let listRowPaddingH: CGFloat = 8
        static let listRowPaddingV: CGFloat = 8
        static let compactRowPaddingV: CGFloat = 6

        static func rowPaddingV(compact: Bool) -> CGFloat { compact ? compactRowPaddingV : listRowPaddingV }
        static func rowIcon(compact: Bool) -> CGFloat { compact ? serviceIconCompact : serviceIcon }
        /// The list's own inset from the window edge, so the fill clears it.
        static let listInset: CGFloat = 6
        /// Where a row's text starts. Headers, search and footers line up on it.
        static let contentInset: CGFloat = listInset + listRowPaddingH
        static let groupHeaderInsets = EdgeInsets(top: 6, leading: listRowPaddingH, bottom: 4, trailing: listRowPaddingH)
        /// Hover actions sit a little outside the text edge, so their glyphs and
        /// not their hit areas line up with the path they cover.
        static let headerActionsInset: CGFloat = listRowPaddingH - 4
        /// The label column of a detail card, wide enough for "Working directory".
        static let factLabelWidth: CGFloat = 118
        static let treeIndent: CGFloat = 18
        static let serviceIcon: CGFloat = 16
        static let serviceIconCompact: CGFloat = 14
        /// Beside a service name on the bottom line of a project-first cell.
        static let serviceIconSmall: CGFloat = 13
        /// The least of a project path a long project name may leave, so the
        /// last folder still reads as "…/wishfox-api".
        static let pathMinWidth: CGFloat = 96
        static let statusPillWidth: CGFloat = 38
        /// Wide enough for "100%" in `portCaption` with monospaced digits.
        static let cpuLabelWidth: CGFloat = 28
        static let projectIcon: CGFloat = 16

        /// The icon buttons beside the app name, in the popover and the dashboard.
        static let headerButtonSize: CGFloat = 22
        static let headerSymbolSize: CGFloat = 12
        static let dashboardWidth: CGFloat = 1180
        static let dashboardHeight: CGFloat = 820
        static let sidebarWidth: CGFloat = 300
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

    static let portName = Font.system(size: 12.5, weight: .semibold)
    static let portSubtitle = Font.mono(11)
    static let portPort = Font.mono(12, .medium)
    static let portSectionLabel = Font.system(size: 12, weight: .medium)
    static let portGroupLabel = Font.system(size: 10.5, weight: .semibold)
    /// Proportional secondary text: subtitles, summary labels, fact labels.
    static let portDetail = Font.system(size: 12)
    static let portCaption = Font.system(size: 11)
    static let portBadge = Font.system(size: 9, weight: .bold)
    /// Every version number: services, plugins, projects and Portfox itself.
    static let portVersion = Font.mono(11)
}

extension View {
    /// Every surface root wears this, and it is the only thing driving the
    /// palette: the tokens resolve against `\.colorScheme`. `preferredColorScheme`
    /// would be the obvious choice and is not usable, because it is a scene
    /// preference and no-ops under `ImageRenderer`.
    func themedSurface(_ scheme: ColorScheme) -> some View {
        environment(\.colorScheme, scheme)
    }

    /// Every group and section title: small, uppercase, tracked out.
    func groupLabelStyle() -> some View {
        font(.portGroupLabel)
            .textCase(.uppercase)
            .tracking(0.7)
            .foregroundStyle(Theme.secondaryText)
    }
}
