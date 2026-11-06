#!/usr/bin/env swift
// Editable vector artwork, rendered with AppKit. No image libraries required.
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "assets", isDirectory: true)
let manager = FileManager.default
try manager.createDirectory(at: output, withIntermediateDirectories: true)
let temporary = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
let iconset = temporary.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try manager.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? manager.removeItem(at: temporary) }

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func polygon(_ points: [(CGFloat, CGFloat)]) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: points[0].0, y: points[0].1))
    for point in points.dropFirst() { path.line(to: NSPoint(x: point.0, y: point.1)) }
    path.close()
    return path
}

func render(size: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)

    // Inset rounded tile and a soft shadow match the visual size of macOS icons.
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 184, yRadius: 184)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    color(0x121E33).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0x0B1221), ending: color(0x24364C))!.draw(in: tile, angle: 65)
    color(0xFFFFFF, alpha: 0.13).setStroke()
    tile.lineWidth = 2
    tile.stroke()

    // Three planes make one unmistakable 3D object. Wide negative space keeps
    // the silhouette legible in the Dock and at 16px in Finder.
    let top = polygon([(512, 770), (744, 638), (512, 504), (280, 638)])
    let left = polygon([(280, 638), (512, 504), (512, 238), (280, 372)])
    let right = polygon([(512, 504), (744, 638), (744, 372), (512, 238)])
    NSGraphicsContext.saveGraphicsState()
    let markShadow = NSShadow()
    markShadow.shadowColor = color(0x000812, alpha: 0.5)
    markShadow.shadowBlurRadius = 28
    markShadow.shadowOffset = NSSize(width: 0, height: -16)
    markShadow.set()
    color(0x38C9CF).setFill()
    polygon([(512, 770), (744, 638), (744, 372), (512, 238), (280, 372), (280, 638)]).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0xCEFFF3), ending: color(0x65E6DB))!.draw(in: top, angle: 30)
    NSGradient(starting: color(0x25B3C3), ending: color(0x64DED6))!.draw(in: left, angle: 80)
    NSGradient(starting: color(0x2676BE), ending: color(0x42C5DB))!.draw(in: right, angle: 80)

    // Fine illuminated edges add depth without adding another symbol.
    let edges = NSBezierPath()
    edges.move(to: NSPoint(x: 280, y: 638))
    edges.line(to: NSPoint(x: 512, y: 504))
    edges.line(to: NSPoint(x: 744, y: 638))
    edges.move(to: NSPoint(x: 512, y: 504))
    edges.line(to: NSPoint(x: 512, y: 238))
    edges.lineWidth = 3
    edges.lineJoinStyle = .round
    color(0xD6FFF5, alpha: 0.32).setStroke()
    edges.stroke()

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        let data = render(size: points * scale)
        try data.write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
        if points == 512 && scale == 2 {
            try data.write(to: output.appendingPathComponent("AppIcon.png"))
        }
    }
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["--convert", "icns", "--output", output.appendingPathComponent("AppIcon.icns").path, iconset.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
print("Generated AppIcon.png and AppIcon.icns in \(output.path)")
