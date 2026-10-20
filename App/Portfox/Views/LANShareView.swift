import PortfoxKit
import SwiftUI

/// A QR code and the URL a phone on the same network opens.
struct LANShareView: View {
    @Environment(AppState.self) private var state

    /// Read once when the popover opens, so it neither flickers through an empty
    /// first frame nor regenerates the code on a redraw.
    @State private var url: URL?
    @State private var code: NSImage?

    init(service: RunningService) {
        let url = LocalNetwork.ipv4Address().flatMap { service.networkURL(macAddress: $0) }
        _url = State(initialValue: url)
        _code = State(initialValue: url.flatMap { LocalNetwork.qrCode(for: $0) })
    }

    var body: some View {
        VStack(spacing: 10) {
            if let url {
                if let code {
                    Image(nsImage: code)
                        .interpolation(.none)
                        .padding(8)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                Text(url.absoluteString)
                    .font(.portSubtitle)
                    .foregroundStyle(Theme.primaryText)
                    .textSelection(.enabled)
                ActionButton(symbol: "doc.on.doc", label: "Copy URL", tint: Theme.primaryText) {
                    state.copy(url.absoluteString)
                }
            } else {
                Text("This Mac is not on a network another device can reach.")
                    .font(.portDetail)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(width: 184)
            }
        }
        .padding(14)
    }
}
