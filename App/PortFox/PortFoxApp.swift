import PortFoxKit
import SwiftUI

@main
struct PortFoxApp: App {
    @State private var state = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environment(state)
        } label: {
            MenuBarLabel(serviceCount: state.serviceCount)
        }
        .menuBarExtraStyle(.window)
        .onChange(of: delegate.isReady, initial: true) {
            guard delegate.isReady, let request = SnapshotRenderer.request else { return }
            Task { await SnapshotRenderer.run(request, state: state) }
        }

        Window("PortFox", id: WindowPresenter.dashboardSceneID) {
            DashboardView()
                .environment(state)
                .frame(minWidth: 900, minHeight: 620)
        }
        .defaultSize(width: Theme.Metrics.dashboardWidth, height: Theme.Metrics.dashboardHeight)
        .defaultPosition(.center)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        // The app is LSUIElement, so this menu is never drawn. It still matters,
        // because `NSApplication.sendEvent` offers every key-down to the main menu
        // whether or not it is visible, and without these items Cmd+C, Cmd+V,
        // Cmd+A and Cmd+Z do nothing in the dashboard's search field.
        .commands {
            TextEditingCommands()
            CommandGroup(replacing: .appTermination) {
                Button("Quit PortFox") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
            // SwiftUI adds Close for a WindowGroup but not for a single Window.
            CommandGroup(after: .windowSize) {
                Button("Close") { NSApp.keyWindow?.performClose(nil) }
                    .keyboardShortcut("w")
            }
        }
        .restorationBehavior(.disabled)
    }
}

/// Only exists so snapshot rendering can wait for a running app.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var isReady = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        isReady = true
    }

    /// Closing the dashboard must never quit a menu bar app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

private struct MenuBarLabel: View {
    let serviceCount: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(.menuBarFox)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 13, height: 13)
            if serviceCount > 0 {
                Text(String(serviceCount))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
        }
    }
}
