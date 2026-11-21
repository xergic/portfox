import PortfoxKit
import SwiftUI

/// The dashboard scene root. Owns the window chrome, its sheets and the close
/// observer. Everything renderable lives in `DashboardContent`.
struct DashboardView: View {
    @Environment(AppState.self) private var state
    @State private var dashboard = DashboardState()
    @State private var window: NSWindow?

    var body: some View {
        @Bindable var state = state

        DashboardContent(dashboard: dashboard)
            .environment(state)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .themedSurface(state.appearance.colorScheme)
            .background(WindowAccessor(onAttach: attach(_:)))
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
                guard let closing = note.object as? NSWindow, closing === window else { return }
                state.dashboardDidDisappear()
            }
            .sheet(item: $state.presentedSheet, onDismiss: state.sheetDidDismiss) { sheet in
                Group {
                    switch sheet {
                    case .preferences: PreferencesSheet()
                    case .about: AboutSheet()
                    }
                }
                .environment(state)
                .allowsAppTermination()
            }
            .onAppear { state.dashboardDidAppear() }
            .onChange(of: state.result.services.map(\.id)) {
                dashboard.forgetProbes(missingFrom: state.result)
            }
            // `attach` runs once per window, so a preference flipped while the
            // dashboard is open would leave the AppKit chrome on the old theme.
            .onChange(of: state.appearance.colorScheme) {
                if let window { applyAppearance(to: window) }
            }
    }

    /// Activation has to happen here rather than beside `openWindow`, because at
    /// that point the window does not exist yet and there is nothing to raise.
    private func attach(_ window: NSWindow) {
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.isRestorable = false
        applyAppearance(to: window)
    }

    /// The window is drawn by SwiftUI, but its own background flashes the other
    /// theme during a resize without this.
    private func applyAppearance(to window: NSWindow) {
        window.appearance = state.appearance.nsAppearance
        window.backgroundColor = NSColor(Theme.background)
    }
}

private extension View {
    /// An attached sheet vetoes Sparkle's quit. `AppState.checkForUpdates` closes
    /// the sheet first, this covers one opened while the update downloads.
    @ViewBuilder func allowsAppTermination() -> some View {
        if #available(macOS 15.4, *) {
            presentationPreventsAppTermination(false)
        } else {
            self
        }
    }
}
