import AppKit
// Converts the Midjourney icon artwork into a macOS .icns (Apple icon grid: 824 pt tile on a 1024 canvas).
let root = CommandLine.arguments[1]
let src = NSImage(contentsOfFile: "\(root)/assets/branding/midjourney-icon-source.png")!
let crop = NSRect(x: 150, y: 1024 - 874, width: 724, height: 724) // tile region (AppKit origin bottom-left)
let iconset = "\(root)/build/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconset)
try! FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for (size, names) in [(16, ["16x16"]), (32, ["16x16@2x", "32x32"]), (64, ["32x32@2x"]), (128, ["128x128"]), (256, ["128x128@2x", "256x256"]),
                      (512, ["256x256@2x", "512x512"]), (1024, ["512x512@2x"])] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let s = CGFloat(size) / 1024
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s).addClip()
    src.draw(in: tile.insetBy(dx: -8 * s, dy: -8 * s), from: crop, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    let png = rep.representation(using: .png, properties: [:])!
    for n in names { try! png.write(to: URL(fileURLWithPath: "\(iconset)/icon_\(n).png")) }
    if size == 1024 { try! png.write(to: URL(fileURLWithPath: "\(root)/assets/branding/app-icon-1024.png")) }
}
