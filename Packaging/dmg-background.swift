import AppKit

// Render both resolutions so Finder uses a sharp background on Retina displays.
let width: CGFloat = 760
let height: CGFloat = 560
guard CommandLine.arguments.count == 3 else {
    throw NSError(domain: "ScreenSharingProxyPackaging", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "Usage: dmg-background.swift OUTPUT_PREFIX APP_BUNDLE"
    ])
}
let output = CommandLine.arguments[1]
let app = URL(fileURLWithPath: CommandLine.arguments[2])
let infoData = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
guard let info = try PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any],
      info["CFBundleIdentifier"] as? String == "com.andotsy.screensharing-proxy",
      let version = info["SSPReleaseVersion"] as? String,
      version.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+(-alpha\.[0-9]+)?$"#, options: .regularExpression) != nil,
      let minimumSystemVersion = info["LSMinimumSystemVersion"] as? String,
      minimumSystemVersion.range(of: #"^[0-9]+(?:\.[0-9]+){0,2}$"#, options: .regularExpression) != nil else {
    throw NSError(domain: "ScreenSharingProxyPackaging", code: 2, userInfo: [
        NSLocalizedDescriptionKey: "Screen Sharing Rubyfier's bundle version or minimum macOS version is missing or invalid."
    ])
}
var osComponents = minimumSystemVersion.split(separator: ".")
while osComponents.count > 1, osComponents.last == "0" { osComponents.removeLast() }
let systemLabel = "macOS \(osComponents.joined(separator: "."))+  ·  Apple silicon"

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
    NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
}

func rect(_ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
    NSRect(x: x, y: height - top - h, width: w, height: h)
}

func text(_ value: String, x: CGFloat, top: CGFloat, w: CGFloat,
          size: CGFloat, weight: NSFont.Weight, ink: NSColor,
          alignment: NSTextAlignment = .left) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    (value as NSString).draw(in: rect(x, top, w, size * 1.5), withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: ink,
        .paragraphStyle: paragraph,
    ])
}

for scale in [1, 2] {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(width) * scale, pixelsHigh: Int(height) * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    bitmap.size = NSSize(width: width, height: height)
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    // NSGraphicsContext derives Retina scaling from bitmap.size.

    NSGradient(starting: color(247, 250, 255), ending: color(230, 239, 252))!
        .draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -75)

    let dark = color(22, 42, 68)
    let muted = color(86, 108, 136)
    let blue = color(45, 109, 234)
    text("SCREEN SHARING RUBYFIER", x: 54, top: 28, w: 300, size: 12, weight: .bold, ink: blue)
    text("Install Screen Sharing Rubyfier", x: 54, top: 53, w: 610, size: 32, weight: .bold, ink: dark)
    text("Drag the app to Applications.", x: 55, top: 101, w: 600, size: 17, weight: .regular, ink: muted)
    text("v\(version)", x: 584, top: 29, w: 122, size: 12, weight: .medium,
         ink: muted, alignment: .right)

    let card = NSBezierPath(roundedRect: rect(54, 151, 652, 157), xRadius: 24, yRadius: 24)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(50, 80, 125).withAlphaComponent(0.08)
    shadow.shadowBlurRadius = 18
    shadow.shadowOffset = NSSize(width: 0, height: -5)
    shadow.set()
    NSColor.white.withAlphaComponent(0.88).setFill()
    card.fill()
    NSGraphicsContext.restoreGraphicsState()

    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 329, y: height - 213))
    arrow.line(to: NSPoint(x: 424, y: height - 213))
    arrow.move(to: NSPoint(x: 402, y: height - 191))
    arrow.line(to: NSPoint(x: 424, y: height - 213))
    arrow.line(to: NSPoint(x: 402, y: height - 235))
    arrow.lineWidth = 7
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    blue.setStroke()
    arrow.stroke()

    text("App blocked? Copy the README commands into Terminal.", x: 54, top: 327, w: 652, size: 15,
         weight: .medium, ink: muted, alignment: .center)
    text(systemLabel, x: 54, top: 476, w: 652, size: 11,
         weight: .regular, ink: muted, alignment: .center)

    NSGraphicsContext.restoreGraphicsState()
    let suffix = scale == 1 ? ".png" : "@2x.png"
    try bitmap.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: output + suffix))
}
