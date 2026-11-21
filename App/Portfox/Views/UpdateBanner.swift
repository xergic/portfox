import SwiftUI

/// Sticky row above a bottom bar while a scheduled check has an update waiting.
struct UpdateBanner: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if let version = Updater.shared.pendingVersion {
            Button { state.checkForUpdates() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("\(AppInfo.name) \(Text(version).font(.mono(11, .medium))) is available")
                    Spacer(minLength: 8)
                    Text("Update…").fontWeight(.semibold)
                }
                .font(.portCaption)
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, Theme.Metrics.contentInset)
                .frame(minHeight: 28)
                .background(Theme.accent)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show the release notes and install")
        }
    }
}
