import AppKit
import CoreImage.CIFilterBuiltins
import Darwin
import Foundation
import PortfoxKit

/// How a phone on the same network reaches a service on this Mac.
enum LocalNetwork {
    /// The Mac's IPv4 address on its primary interface. Read when asked, never on
    /// the refresh tick, because only an open QR code or a copy needs it.
    ///
    /// Wi-Fi and Ethernet are both `en*`, and `en0` is the built-in one, so it is
    /// preferred. Link-local `169.254` addresses are skipped: a phone never has one.
    static func ipv4Address() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        var fallback: String?
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(entry.pointee.ifa_flags)
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0 else { continue }
            let interface = String(cString: entry.pointee.ifa_name)
            guard interface.hasPrefix("en") else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let text = String(cString: host)
            guard !text.hasPrefix("169.254.") else { continue }
            if interface == "en0" { return text }
            fallback = fallback ?? text
        }
        return fallback
    }

    /// Scaled with nearest-neighbour sampling, because a smoothed QR code is a
    /// blurred one and phone cameras read blur badly.
    static func qrCode(for url: URL, side: CGFloat = 168) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = side / output.extent.width
        let scaled = output.samplingNearest().transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let representation = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}

@MainActor
extension AppState {
    /// The URL for a web service, `host:port` for anything else, so a database on
    /// `0.0.0.0` can be pasted into a client on another machine.
    func copyNetworkAddress(_ service: RunningService) {
        guard let host = LocalNetwork.ipv4Address(), let address = service.networkAddress(macAddress: host) else {
            report("This Mac is not on a network another device can reach.")
            return
        }
        copy(service.networkURL(macAddress: host)?.absoluteString ?? address)
    }
}
