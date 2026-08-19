import AppKit
import SwiftUI

/// Renders a surface to a PNG and exits. Lets the design be checked against the
/// reference screenshots without Screen Recording permission, and without
/// hand-driving the menu bar.
///
/// Usage: `PortFox --snapshot out.png [--hover]`, `--snapshot-dashboard out.png`,
/// or `--snapshot-prefs out.png`.
@MainActor
enum SnapshotRenderer {
    enum Surface: String {
        case popover = "--snapshot"
        case dashboard = "--snapshot-dashboard"
        case preferences = "--snapshot-prefs"
    }

    struct Request {
        let surface: Surface
        let path: String
    }

    static var request: Request? {
        let arguments = CommandLine.arguments
        for surface in [Surface.popover, .dashboard, .preferences] {
            guard let index = arguments.firstIndex(of: surface.rawValue), index + 1 < arguments.count else { continue }
            return Request(surface: surface, path: arguments[index + 1])
        }
        return nil
    }

    /// Any snapshot flag at all, so the presenter knows not to open a real window.
    static var requestedPath: String? { request?.path }

    static func run(_ request: Request, state: AppState) async {
        // The surface has to announce itself the way a real window does, or the
        // state it renders is the state PortFox keeps while nothing is on screen.
        switch request.surface {
        case .popover: state.popoverDidAppear()
        case .dashboard: state.dashboardDidAppear()
        case .preferences: break
        }
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

    /// `preferredColorScheme` is a scene preference and does nothing here, so every
    /// surface sets the environment value the way `MenuView` already does.
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
                .environment(\.colorScheme, .dark)
        case .preferences:
            PreferencesSheet(scrolls: false)
                .environment(state)
        }
    }
}
