// Draws Crest's app icon from the same mark the website uses.
//
// The web logo lives as an SVG in crest-web/app/components/icons.tsx. There is no
// SVG rasteriser on this machine, and adding one as a build dependency to render
// four shapes would be the wrong trade. The geometry is reproduced here in the
// same 24-unit coordinate space the SVG uses, so the two stay legible against each
// other: change one, change the other, and the numbers line up line for line.
//
//   swift packaging/icon/GenerateAppIcon.swift <output-directory>

import AppKit
import CoreGraphics
import Foundation

// The SVG viewBox. Every constant below is in these units.
let unit: CGFloat = 24

// macOS icons do not fill their canvas. The rounded square sits inside a margin
// that the Dock, Finder and the App Switcher all rely on for optical alignment, so
// an icon drawn edge to edge reads as noticeably larger than every other icon
// beside it. Apple's grid puts the square at roughly 82% of the canvas.
let inset: CGFloat = 0.82

struct Palette {
    static let plate = CGColor(red: 0x12 / 255, green: 0x12 / 255, blue: 0x12 / 255, alpha: 1)
    static let edge = CGColor(red: 0x24 / 255, green: 0x27 / 255, blue: 0x28 / 255, alpha: 1)
    static let ring = CGColor(red: 0x43 / 255, green: 0x43 / 255, blue: 0x45 / 255, alpha: 1)
    static let arc = CGColor(red: 0x59 / 255, green: 0xd4 / 255, blue: 0x99 / 255, alpha: 1)
    static let core = CGColor(red: 0xf4 / 255, green: 0xf4 / 255, blue: 0xf6 / 255, alpha: 1)
}

func drawIcon(size: CGFloat) -> CGImage? {
    let pixels = Int(size)
    guard let context = CGContext(
        data: nil, width: pixels, height: pixels,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high

    // Map the SVG's 24-unit, y-down space onto the bitmap, centred and inset.
    let drawn = size * inset
    let margin = (size - drawn) / 2
    let scale = drawn / unit

    context.translateBy(x: margin, y: margin + drawn)
    context.scaleBy(x: scale, y: -scale)

    // Plate. The stroke sits on the path, so the rect is inset by half its width
    // to keep the outer edge exactly where the SVG puts it.
    let plate = CGRect(x: 1, y: 1, width: 22, height: 22)
    let plated = CGPath(roundedRect: plate, cornerWidth: 6, cornerHeight: 6, transform: nil)
    context.addPath(plated)
    context.setFillColor(Palette.plate)
    context.fillPath()

    context.addPath(plated)
    context.setStrokeColor(Palette.edge)
    context.setLineWidth(1)
    context.strokePath()

    // Full ring.
    context.addEllipse(in: CGRect(x: 12 - 6.4, y: 12 - 6.4, width: 12.8, height: 12.8))
    context.setStrokeColor(Palette.ring)
    context.setLineWidth(1.4)
    context.strokePath()

    // The green sweep, from twelve o'clock clockwise to the SVG's end point.
    // Angles are derived rather than typed so they cannot drift from the geometry:
    // the arc ends at (17.6, 15), which is 5.6 right of and 3 below the centre.
    context.setStrokeColor(Palette.arc)
    context.setLineWidth(1.8)
    context.setLineCap(.round)
    context.addArc(
        center: CGPoint(x: 12, y: 12),
        radius: 6.4,
        startAngle: -.pi / 2,
        endAngle: atan2(3, 5.6),
        clockwise: false
    )
    context.strokePath()

    // Core.
    context.addEllipse(in: CGRect(x: 12 - 1.7, y: 12 - 1.7, width: 3.4, height: 3.4))
    context.setFillColor(Palette.core)
    context.fillPath()

    return context.makeImage()
}

// name → pixel size, matching the asset catalog already in the project.
let outputs: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: swift GenerateAppIcon.swift <output-directory>\n".utf8))
    exit(64)
}
let directory = URL(fileURLWithPath: arguments[1])

for (name, size) in outputs {
    guard let image = drawIcon(size: size) else {
        FileHandle.standardError.write(Data("could not draw \(name)\n".utf8))
        exit(1)
    }
    let url = directory.appendingPathComponent(name + ".png")
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        exit(1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    print("wrote \(name).png at \(Int(size))px")
}
