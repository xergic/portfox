#!/usr/bin/env swift
// Draws the PortFox app icon and writes the macOS AppIcon set.
// Run from the repository root:  swift Tools/make-appicon.swift

import AppKit
import CoreGraphics
import Foundation

let destination = URL(fileURLWithPath: "App/PortFox/Resources/Assets.xcassets/AppIcon.appiconset")

/// Same geometry as MenuBarFox.svg, in a 24 unit box with y pointing down.
func foxPath(in box: CGRect) -> CGPath {
    let unit = box.width / 24
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: box.minX + x * unit, y: box.minY + y * unit)
    }

    let path = CGMutablePath()
    path.move(to: point(3.2, 3.1))
    path.addLine(to: point(9.0, 8.4))
    path.addCurve(to: point(15.0, 8.4), control1: point(10.93, 7.87), control2: point(13.07, 7.87))
    path.addLine(to: point(20.8, 3.1))
    path.addLine(to: point(20.8, 13.2))
    path.addCurve(to: point(12, 21.5), control1: point(20.8, 17.75), control2: point(16.86, 21.5))
    path.addCurve(to: point(3.2, 13.2), control1: point(7.14, 21.5), control2: point(3.2, 17.75))
    path.closeSubpath()

    for eyeX in [8.9, 15.1] as [CGFloat] {
        let centre = point(eyeX, 13.3)
        path.addEllipse(in: CGRect(x: centre.x - 1.2 * unit, y: centre.y - 1.2 * unit,
                                   width: 2.4 * unit, height: 2.4 * unit))
    }

    let muzzle = CGMutablePath()
    muzzle.move(to: point(10.75, 16.05))
    muzzle.addLine(to: point(13.25, 16.05))
    muzzle.addLine(to: point(12, 18.35))
    muzzle.closeSubpath()
    path.addPath(muzzle)

    return path
}

func render(size: Int) -> Data {
    let dimension = CGFloat(size)
    guard let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("cannot create bitmap context") }

    // Flip to a y-down space so the path geometry matches the SVG.
    context.translateBy(x: 0, y: dimension)
    context.scaleBy(x: 1, y: -1)

    let inset = dimension * 0.09
    let plate = CGRect(x: inset, y: inset, width: dimension - inset * 2, height: dimension - inset * 2)
    let radius = plate.width * 0.2237

    context.saveGState()
    context.addPath(CGPath(roundedRect: plate, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1),
            CGColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: plate.minY),
                               end: CGPoint(x: 0, y: plate.maxY), options: [])
    context.restoreGState()

    let markSize = plate.width * 0.62
    let mark = CGRect(x: plate.midX - markSize / 2, y: plate.midY - markSize / 2,
                      width: markSize, height: markSize)
    context.addPath(foxPath(in: mark))
    context.setFillColor(CGColor(red: 0.98, green: 0.55, blue: 0.24, alpha: 1))
    context.fillPath(using: .evenOdd)

    guard let image = context.makeImage() else { fatalError("cannot render icon") }
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("cannot encode PNG")
    }
    return data
}

let entries: [(size: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)
]

try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

var images: [[String: String]] = []
var written: Set<Int> = []

for entry in entries {
    let pixels = entry.size * entry.scale
    let filename = "icon-\(pixels).png"
    if written.insert(pixels).inserted {
        try render(size: pixels).write(to: destination.appendingPathComponent(filename))
    }
    images.append([
        "filename": filename,
        "idiom": "mac",
        "scale": "\(entry.scale)x",
        "size": "\(entry.size)x\(entry.size)"
    ])
}

let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: destination.appendingPathComponent("Contents.json"))

print("wrote \(written.count) sizes to \(destination.path)")
