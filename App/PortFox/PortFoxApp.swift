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
            guard delegate.isReady, let path = SnapshotRenderer.requestedPath else { return }
            Task { await SnapshotRenderer.run(path: path, state: state) }
        }

        Settings {
            SettingsView()
                .environment(state)
        }
    }
}

/// Only exists so snapshot rendering can wait for a running app.
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var isReady = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        isReady = true
    }
}

private struct MenuBarLabel: View {
    let serviceCount: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(.menuBarFox)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 17, height: 17)
            if serviceCount > 0 {
                Text(String(serviceCount))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
        }
    }
}
