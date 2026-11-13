#!/usr/bin/env swift
// Artwork contains no app/folder icons or filenames: Finder supplies those.
// Coordinates are in points, with a top-left origin, matching settings.py.
import AppKit

let product = "Portfox"
let eyebrow = "Know what’s listening"
let site = "portfox.kandera.cz"
let accent = NSColor(srgbRed: 0, green: 200.0 / 255, blue: 189.0 / 255, alpha: 1)
let canvas = NSSize(width: 640, height: 520)

guard CommandLine.arguments.count == 2 else {
    fatalError("usage: swift render-background.swift <output.tiff>")
}

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
    NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
}

func text(_ value: String, at point: NSPoint, size: CGFloat,
          weight: NSFont.Weight = .regular, color: NSColor) {
    (value as NSString).draw(at: point, withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color
    ])
}

func render(scale: Int) -> NSBitmapImageRep {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(canvas.width) * scale,
        pixelsHigh: Int(canvas.height) * scale, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Cannot create the installer background bitmap")
    }
    bitmap.size = canvas
    NSGraphicsContext.saveGraphicsState()
    let context = graphics.cgContext
    context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    context.translateBy(x: 0, y: canvas.height)
    context.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

    color(14, 14, 16).setFill()
    NSRect(origin: .zero, size: canvas).fill()
    if let glow = NSGradient(starting: accent.withAlphaComponent(0.09), ending: accent.withAlphaComponent(0)) {
        glow.draw(fromCenter: NSPoint(x: 550, y: 10), radius: 0,
                  toCenter: NSPoint(x: 550, y: 10), radius: 500, options: [])
    }

    accent.setFill()
    NSBezierPath(ovalIn: NSRect(x: 40, y: 35, width: 6, height: 6)).fill()
    text(eyebrow, at: NSPoint(x: 54, y: 29), size: 12, weight: .medium, color: color(184, 181, 176))
    let heading = NSMutableAttributedString(string: "Install ", attributes: [
        .font: NSFont.systemFont(ofSize: 40, weight: .bold),
        .foregroundColor: color(242, 241, 239), .kern: -1.8
    ])
    heading.append(NSAttributedString(string: "\(product).", attributes: [
        .font: NSFont.systemFont(ofSize: 40, weight: .bold),
        .foregroundColor: accent, .kern: -1.8
    ]))
    heading.draw(at: NSPoint(x: 40, y: 55))

    for centerX: CGFloat in [137, 503] {
        // Frame the icon and filename together, leaving space around Finder’s selection ring.
        let slot = NSBezierPath(roundedRect: NSRect(x: centerX - 88, y: 112, width: 176, height: 204),
                                xRadius: 24, yRadius: 24)
        accent.withAlphaComponent(0.035).setFill()
        slot.fill()
        accent.withAlphaComponent(0.34).setStroke()
        slot.lineWidth = 1
        slot.stroke()
        // Finder controls label text color; a light backplate keeps it readable.
        color(238, 237, 240).setFill()
        NSBezierPath(roundedRect: NSRect(x: centerX - 55, y: 272, width: 110, height: 30),
                     xRadius: 5, yRadius: 5).fill()
    }

    accent.setStroke()
    let arrow = NSBezierPath()
    arrow.lineWidth = 2
    arrow.move(to: NSPoint(x: 282, y: 200))
    arrow.line(to: NSPoint(x: 358, y: 200))
    arrow.move(to: NSPoint(x: 350, y: 192))
    arrow.line(to: NSPoint(x: 358, y: 200))
    arrow.line(to: NSPoint(x: 350, y: 208))
    arrow.stroke()

    let instruction = "Drag \(product) to Applications to get started."
    let instructionFont = NSFont.systemFont(ofSize: 14)
    let instructionWidth = (instruction as NSString).size(withAttributes: [.font: instructionFont]).width
    text(instruction, at: NSPoint(x: (canvas.width - instructionWidth) / 2, y: 333),
         size: 14, color: color(184, 181, 176))
    NSColor.white.withAlphaComponent(0.07).setFill()
    NSRect(x: 40, y: 376, width: 560, height: 1).fill()
    text(product, at: NSPoint(x: 40, y: 392), size: 11, weight: .semibold, color: color(165, 165, 174))
    let siteWidth = (site as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width
    text(site, at: NSPoint(x: 600 - siteWidth, y: 392), size: 11, color: color(127, 127, 138))
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

// Multi-resolution TIFF keeps Finder's background sharp on Retina displays.
let representations = [render(scale: 1), render(scale: 2)]
guard let data = NSBitmapImageRep.representationOfImageReps(in: representations, using: .tiff,
    properties: [.compressionMethod: NSBitmapImageRep.TIFFCompression.lzw.rawValue]) else {
    fatalError("Cannot encode the installer background")
}
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
