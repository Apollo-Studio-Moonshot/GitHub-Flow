import AppKit
import Foundation

// Draws the GitHub Flow app icon at 1024×1024 and writes a PNG.
// Usage: swift scripts/make-icon.swift <output.png>

let size = 1024
let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Support/icon_1024.png"

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    FileHandle.standardError.write(Data("Unable to create bitmap\n".utf8))
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let canvas = NSRect(x: 0, y: 0, width: size, height: size)
NSColor.clear.setFill()
canvas.fill()

// Rounded body with the brand gradient.
let bodyRect = canvas.insetBy(dx: 72, dy: 72)
let body = NSBezierPath(roundedRect: bodyRect, xRadius: 216, yRadius: 216)

let topColor = NSColor(srgbRed: 0.46, green: 0.42, blue: 0.98, alpha: 1)
let bottomColor = NSColor(srgbRed: 0.20, green: 0.53, blue: 0.96, alpha: 1)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.shadowBlurRadius = 34
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
body.fill()
NSGraphicsContext.restoreGraphicsState()

if let gradient = NSGradient(colors: [topColor, bottomColor]) {
    gradient.draw(in: body, angle: -62)
}

// Glossy highlight across the upper half.
NSGraphicsContext.saveGraphicsState()
body.addClip()
let highlight = NSBezierPath(ovalIn: NSRect(x: -80, y: 470, width: 1184, height: 760))
NSColor.white.withAlphaComponent(0.10).setFill()
highlight.fill()
NSGraphicsContext.restoreGraphicsState()

// Subtle inner border.
NSColor.white.withAlphaComponent(0.22).setStroke()
body.lineWidth = 3
body.stroke()

// Branch mark: two nodes on the trunk, one on a fork.
let strokeColor = NSColor.white.withAlphaComponent(0.97)
let strokeWidth: CGFloat = 54

func dot(_ point: NSPoint, radius: CGFloat = 74) {
    let rect = NSRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
    let path = NSBezierPath(ovalIn: rect)
    NSColor.white.withAlphaComponent(0.16).setFill()
    path.fill()
    strokeColor.setStroke()
    path.lineWidth = 26
    path.stroke()
    NSColor.white.setFill()
    NSBezierPath(ovalIn: rect.insetBy(dx: 30, dy: 30)).fill()
}

let trunkX: CGFloat = 356
let bottom = NSPoint(x: trunkX, y: 268)
let top = NSPoint(x: trunkX, y: 704)
let fork = NSPoint(x: 668, y: 588)

// Trunk.
let trunk = NSBezierPath()
trunk.move(to: bottom)
trunk.line(to: top)
trunk.lineCapStyle = .round
trunk.lineWidth = strokeWidth
strokeColor.setStroke()
trunk.stroke()

// Fork curve.
let curve = NSBezierPath()
curve.move(to: NSPoint(x: trunkX, y: 470))
curve.curve(
    to: fork,
    controlPoint1: NSPoint(x: trunkX, y: 620),
    controlPoint2: NSPoint(x: 520, y: 588)
)
curve.lineCapStyle = .round
curve.lineWidth = strokeWidth
strokeColor.setStroke()
curve.stroke()

dot(bottom)
dot(top)
dot(fork)

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("Unable to encode PNG\n".utf8))
    exit(1)
}

do {
    try png.write(to: URL(fileURLWithPath: outputPath))
    print("Wrote \(outputPath)")
} catch {
    FileHandle.standardError.write(Data("Unable to write PNG: \(error)\n".utf8))
    exit(1)
}
