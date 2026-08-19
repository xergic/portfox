import PortFoxKit
import SwiftUI

/// Resolves an icon in the priority order of spec section 8.2: the project's own
/// icon, then the bundled framework logo, then an SF Symbol.
struct ServiceIconView: View {
    let type: ServiceType
    var projectIconPath: String?
    var size: CGFloat = Theme.Metrics.serviceIcon

    var body: some View {
        Group {
            if let image = projectIconPath.flatMap(Self.loadImage) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
            } else if let logo = NSImage(named: type.iconAssetName) {
                Image(nsImage: logo)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: type.fallbackSymbol)
                    .font(.system(size: size * 0.78))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(width: size, height: size)
    }

    /// Decoded images are cached because the popover redraws every two seconds.
    private static let cache = NSCache<NSString, NSImage>()

    static func loadImage(at path: String) -> NSImage? {
        if let cached = cache.object(forKey: path as NSString) { return cached }
        guard let image = NSImage(contentsOfFile: path), image.isValid else { return nil }
        cache.setObject(image, forKey: path as NSString)
        return image
    }
}
