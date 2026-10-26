import PortfoxKit
import SwiftUI

/// How an HTTP status reads everywhere it appears: the row pill and the
/// dashboard's Inspect card. One owner, because two had already drifted.
enum HTTPStatusStyle {
    static func tint(_ code: Int) -> Color {
        switch code {
        case 200..<300: Theme.success
        case 300..<400: Theme.accentText
        case 400..<500: Theme.roleWrapper
        default: Theme.danger
        }
    }

    /// "404 Not found". Sentence case, matching every other label in the app.
    static func text(_ code: Int) -> String {
        let reason = HTTPURLResponse.localizedString(forStatusCode: code)
        return "\(String(code)) \(reason.prefix(1).localizedUppercase)\(reason.dropFirst())"
    }

    static func milliseconds(_ latency: Duration) -> String {
        let parts = latency.components
        return "\(parts.seconds * 1000 + parts.attoseconds / 1_000_000_000_000_000) ms"
    }
}

/// The row's health reading, a leaf so a probe landing redraws this pill and
/// not every row around it.
struct HealthPill: View {
    @Environment(AppState.self) private var state
    let service: RunningService

    var body: some View {
        if case .status(let code, let latency) = state.health.readings[service.id] {
            Text(String(code))
                .font(.mono(10, .semibold))
                .foregroundStyle(HTTPStatusStyle.tint(code))
                .frame(width: Theme.Metrics.statusPillWidth, height: 16)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Metrics.badgeRadius, style: .continuous)
                        .fill(HTTPStatusStyle.tint(code).opacity(0.16))
                )
                .help("\(HTTPStatusStyle.text(code)) · \(HTTPStatusStyle.milliseconds(latency))")
        } else if state.checksHealth, service.localURL != nil {
            // Held empty until the first reading, so its arrival does not widen
            // the slot and tip a compact row onto two lines.
            Color.clear.frame(width: Theme.Metrics.statusPillWidth, height: 16)
        }
    }
}
