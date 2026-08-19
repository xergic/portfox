import PortFoxKit
import SwiftUI

/// The dashboard scene root. Owns the window chrome, the preferences sheet and the
/// close observer. Everything renderable lives in `DashboardContent`.
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
            .environment(\.colorScheme, .dark)
            .background(WindowAccessor(onAttach: attach(_:)))
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
                guard let closing = note.object as? NSWindow, closing === window else { return }
                state.dashboardDidDisappear()
            }
            .sheet(item: $state.presentedSheet) { _ in
                PreferencesSheet().environment(state)
            }
            .onAppear { state.dashboardDidAppear() }
            .onChange(of: state.result.services.map(\.id)) {
                dashboard.forgetProbes(missingFrom: state.result)
            }
    }

    /// Activation has to happen here rather than beside `openWindow`, because at
    /// that point the window does not exist yet and there is nothing to raise.
    private func attach(_ window: NSWindow) {
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(Theme.background)
        window.isRestorable = false
    }
}
