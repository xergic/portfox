import AppKit
import SwiftUI

/// Opens the dashboard and gets keyboard focus onto it.
///
/// The app stays `LSUIElement`, so it is never the active application until it
/// asks. Without the activate step the window looks key while every keystroke
/// goes to whatever app was in front.
@MainActor
enum WindowPresenter {
    static let dashboardSceneID = "dashboard"

    static func showDashboard(_ openWindow: OpenWindowAction) {
        // A snapshot run must render offscreen and exit. Opening a real window
        // would flash it on screen and leave the process alive.
        guard SnapshotRenderer.requestedPath == nil else { return }

        openWindow(id: dashboardSceneID)

        // Raises an already-open dashboard. A brand new one activates itself from
        // `DashboardView.attach`, which is the first moment the window exists.
        NSApp.activate()
        dashboardWindow()?.makeKeyAndOrderFront(nil)
    }

    static func dashboardWindow() -> NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(dashboardSceneID) == true }
    }
}

/// Reaches the `NSWindow` behind a SwiftUI scene, so it can be styled and so the
/// view can tell when it closes. `onDisappear` fires inconsistently for windows,
/// including not at all on some close paths, so the close signal comes from
/// `NSWindow.willCloseNotification` instead, observed by the view.
struct WindowAccessor: NSViewRepresentable {
    let onAttach: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        // Nil in makeNSView, because the view is not in a window yet.
        guard let window = view.window, context.coordinator.window !== window else { return }
        context.coordinator.window = window
        onAttach(window)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        var window: NSWindow?
    }
}
