// Generates Resources/AppIcon.icns. Run: swift Scripts/make-icon.swift
import AppKit

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels) / 1024
    // Standard macOS icon grid: an 824pt rounded square centred in 1024.
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: body, xRadius: 186 * s, yRadius: 186 * s)
    NSGradient(colors: [
        NSColor(srgbRed: 0.33, green: 0.36, blue: 0.43, alpha: 1),
        NSColor(srgbRed: 0.09, green: 0.10, blue: 0.13, alpha: 1),
    ])!.draw(in: shape, angle: -90)
    NSColor.white.withAlphaComponent(0.18).setStroke()
    shape.lineWidth = max(1, 6 * s)
    shape.stroke()

    // Magnifying glass.
    let centre = NSPoint(x: 470 * s, y: 560 * s)
    let radius = 190 * s
    let lens = NSBezierPath(ovalIn: NSRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
    NSColor.white.withAlphaComponent(0.12).setFill()
    lens.fill()
    NSColor.white.setStroke()
    lens.lineWidth = 64 * s
    lens.stroke()
    let handle = NSBezierPath()
    let d = (radius + 28 * s) * 0.7071
    handle.move(to: NSPoint(x: centre.x + d, y: centre.y - d))
    handle.line(to: NSPoint(x: 760 * s, y: 270 * s))
    handle.lineWidth = 76 * s
    handle.lineCapStyle = .round
    handle.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources")
let iconset = fm.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
try fm.createDirectory(at: resources, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try task.run()
task.waitUntilExit()
try render(512).write(to: resources.appendingPathComponent("AppIcon-preview.png"))
print(task.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
