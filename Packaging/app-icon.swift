import AppKit

// Original artwork: two endpoints exchange traffic through a central relay.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func stroke(_ points: [NSPoint], color: NSColor, width: CGFloat) {
    let path = NSBezierPath()
    path.move(to: points[0])
    for point in points.dropFirst() { path.line(to: point) }
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    color.setStroke()
    path.stroke()
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let tile = NSBezierPath(roundedRect: NSRect(x: 78, y: 78, width: 868, height: 868), xRadius: 194, yRadius: 194)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowBlurRadius = 28
        shadow.shadowOffset = NSSize(width: 0, height: -12)
        shadow.set()
        NSColor.systemBlue.setFill()
        tile.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(starting: NSColor(srgbRed: 0.10, green: 0.75, blue: 0.80, alpha: 1),
            ending: NSColor(srgbRed: 0.12, green: 0.27, blue: 0.79, alpha: 1))!.draw(in: tile, angle: -70)

        let white = NSColor.white
        let mist = white.withAlphaComponent(0.80)
        for x in [CGFloat(205), CGFloat(711)] {
            let endpoint = NSBezierPath(roundedRect: NSRect(x: x, y: 400, width: 108, height: 224), xRadius: 36, yRadius: 36)
            white.withAlphaComponent(0.18).setFill(); endpoint.fill()
            endpoint.lineWidth = 11; mist.setStroke(); endpoint.stroke()
        }
        stroke([.init(x: 285, y: 580), .init(x: 708, y: 580)], color: white, width: 28)
        stroke([.init(x: 660, y: 630), .init(x: 710, y: 580), .init(x: 660, y: 530)], color: white, width: 28)
        stroke([.init(x: 739, y: 444), .init(x: 316, y: 444)], color: mist, width: 28)
        stroke([.init(x: 364, y: 494), .init(x: 314, y: 444), .init(x: 364, y: 394)], color: mist, width: 28)
        let relay = NSBezierPath(roundedRect: NSRect(x: 442, y: 508, width: 140, height: 140), xRadius: 39, yRadius: 39)
        NSColor(srgbRed: 0.15, green: 0.39, blue: 0.77, alpha: 1).setFill(); relay.fill()
        relay.lineWidth = 16; white.setStroke(); relay.stroke()
        white.setFill(); NSBezierPath(ovalIn: NSRect(x: 498, y: 564, width: 28, height: 28)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
