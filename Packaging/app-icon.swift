import AppKit

// Package the generated artwork at each macOS icon size. Keep its transparent
// canvas and padding rather than drawing a second icon tile.
guard CommandLine.arguments.count == 3,
      let source = NSImage(contentsOfFile: CommandLine.arguments[1]),
      source.size.width > 0, source.size.width == source.size.height else {
    fatalError("Usage: app-icon.swift SOURCE.png OUTPUT.iconset (square PNG required)")
}
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        NSColor.clear.setFill()
        rect.fill(using: .copy)
        source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                    respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high.rawValue])
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
