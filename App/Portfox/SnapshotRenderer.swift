import AppKit
import SwiftUI

/// Renders a surface to a PNG and exits. Lets the design be checked against the
/// reference screenshots without Screen Recording permission, and without
/// hand-driving the menu bar.
///
/// Usage: `Portfox --snapshot out.png [--hover] [--light]`, `--snapshot-dashboard out.png`,
/// `--snapshot-prefs out.png`, `--snapshot-ignored out.png` or
/// `--snapshot-about out.png`.
@MainActor
enum SnapshotRenderer {
    enum Surface: String, CaseIterable {
        case popover = "--snapshot"
        case dashboard = "--snapshot-dashboard"
        case preferences = "--snapshot-prefs"
        case ignored = "--snapshot-ignored"
        case about = "--snapshot-about"
    }

    struct Request {
        let surface: Surface
        let path: String
    }

    static var request: Request? {
        let arguments = CommandLine.arguments
        for surface in Surface.allCases {
            guard let index = arguments.firstIndex(of: surface.rawValue), index + 1 < arguments.count else { continue }
            return Request(surface: surface, path: arguments[index + 1])
        }
        return nil
    }

    /// Any snapshot flag at all, so the presenter knows not to open a real window.
    static var requestedPath: String? { request?.path }

    static func run(_ request: Request, state: AppState) async {
        // The surface has to announce itself the way a real window does, or the
        // state it renders is the state Portfox keeps while nothing is on screen.
        switch request.surface {
        case .popover: state.popoverDidAppear()
        case .dashboard: state.dashboardDidAppear()
        case .preferences, .ignored, .about: break
        }
        if CommandLine.arguments.contains("--light") { state.appearance.force(.light) }
        await state.refresh()

        let renderer = ImageRenderer(content: content(for: request.surface, state: state))
        renderer.scale = 2

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            FileHandle.standardError.write(Data("snapshot failed to render\n".utf8))
            exit(1)
        }

        do {
            try png.write(to: URL(fileURLWithPath: request.path))
            print("wrote \(request.path)")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("snapshot failed to write: \(error)\n".utf8))
            exit(1)
        }
    }

    /// `preferredColorScheme` is a scene preference and does nothing here, so
    /// every surface carries `themedSurface` the way `MenuView` already does.
    /// `.dashboard` hosts `DashboardContent` directly, bypassing the
    /// `DashboardView` that normally wears it, so it applies its own.
    @ViewBuilder
    private static func content(for surface: Surface, state: AppState) -> some View {
        let forcesHover = CommandLine.arguments.contains("--hover")

        switch surface {
        case .popover:
            MenuView(forcesHover: forcesHover, scrolls: false)
                .environment(state)
                .frame(width: Theme.Metrics.popoverWidth)
        case .dashboard:
            DashboardContent(dashboard: DashboardState(), scrolls: false, forcesHover: forcesHover)
                .environment(state)
                .frame(width: Theme.Metrics.dashboardWidth, height: Theme.Metrics.dashboardHeight)
                .background(Theme.background)
                .themedSurface(state.appearance.colorScheme)
        case .preferences:
            PreferencesSheet(scrolls: false)
                .environment(state)
        case .ignored:
            PreferencesSheet(page: .ignored, scrolls: false)
                .environment(state)
        case .about:
            AboutSheet()
        }
    }
}
