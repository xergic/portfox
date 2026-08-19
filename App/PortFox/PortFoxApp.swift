import PortFoxKit
import SwiftUI

@main
struct PortFoxApp: App {
    @State private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environment(state)
        } label: {
            MenuBarLabel(count: state.serviceCount)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(state)
        }
    }
}

private struct MenuBarLabel: View {
    let count: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(.menuBarFox)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 17, height: 17)
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
    }
}
