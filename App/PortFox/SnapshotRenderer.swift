import AppKit
import SwiftUI

/// Renders the popover to a PNG and exits. Lets the design be checked against
/// the reference screenshots without Screen Recording permission, and without
/// hand-driving the menu bar.
///
/// Usage: `PortFox --snapshot /path/to/output.png`
@MainActor
enum SnapshotRenderer {
    static var requestedPath: String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    static func run(path: String, state: AppState) async {
        await state.refresh()

        let renderer = ImageRenderer(
            content: MenuView(scrolls: false, forcesHover: CommandLine.arguments.contains("--hover"))
                .environment(state)
                .frame(width: Theme.Metrics.popoverWidth)
                .preferredColorScheme(.dark)
        )
        renderer.scale = 2

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            FileHandle.standardError.write(Data("snapshot failed to render\n".utf8))
            exit(1)
        }

        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("wrote \(path)")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("snapshot failed to write: \(error)\n".utf8))
            exit(1)
        }
    }
}
