// Draws LeanKeys' app icon (an original "L" monogram with a text cursor) and writes AppIcon.icns next to this file.
// Run from anywhere: swift leankeys/Branding/make-icon.swift
import AppKit
import Foundation

let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("LeanKeys-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

/// Draws at an exact pixel size; lockFocus on an NSImage would render at the screen's scale instead.
func render(_ px: Int) throws -> Data {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let ctx = NSGraphicsContext(bitmapImageRep: rep)
    else { throw NSError(domain: "make-icon", code: 1) }
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let s = CGFloat(px) / 1024 // design grid is 1024 x 1024

    // Body: macOS icon grid, 824 pt square with a 185 pt corner radius, centred.
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(starting: color(0x14B8A6), ending: color(0x1E3A8A))!.draw(in: shape, angle: -60)

    // Monogram: a bold "L" built from two rounded bars.
    color(0xFFFFFF).setFill()
    NSBezierPath(roundedRect: NSRect(x: 300 * s, y: 270 * s, width: 140 * s, height: 480 * s),
                 xRadius: 40 * s, yRadius: 40 * s).fill()
    NSBezierPath(roundedRect: NSRect(x: 300 * s, y: 270 * s, width: 330 * s, height: 130 * s),
                 xRadius: 40 * s, yRadius: 40 * s).fill()

    // Text cursor beside the L.
    color(0xFBBF24).setFill()
    NSBezierPath(roundedRect: NSRect(x: 680 * s, y: 270 * s, width: 60 * s, height: 480 * s),
                 xRadius: 30 * s, yRadius: 30 * s).fill()

    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { throw NSError(domain: "make-icon", code: 2) }
    return png
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let out = here.appendingPathComponent("AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil failed\n".data(using: .utf8)!)
    exit(1)
}
print("wrote \(out.path)")
