import AppKit

// Rasterize the app icon that actool compiled from Packaging/AppIcon.icon into
// the bundle's Assets.car, so the ICNS fallback matches the system rendering.
guard CommandLine.arguments.count == 3,
      let icon = Bundle(url: URL(fileURLWithPath: CommandLine.arguments[1]))?.image(forResource: "AppIcon") else {
    fatalError("Usage: app-icon.swift BUNDLE.app OUTPUT.iconset (bundle with a compiled Assets.car required)")
}
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = NSSize(width: size, height: size)
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
            icon.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
