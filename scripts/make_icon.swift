// Draws the HeatWatch app icon and writes an .iconset folder.
// Usage: swift scripts/make_icon.swift <output.iconset>
// Then:  iconutil -c icns <output.iconset> -o Resources/AppIcon.icns
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

/// Draws on a 1024-point canvas. Origin is bottom-left.
func drawIcon(in context: CGContext) {
    let accent = CGColor(srgbRed: 1.0, green: 0.584, blue: 0.0, alpha: 1)
    let glass = CGColor(srgbRed: 0.95, green: 0.95, blue: 0.96, alpha: 1)
    let channel = CGColor(srgbRed: 0.13, green: 0.13, blue: 0.145, alpha: 1)

    // Body: macOS icon grid, 824-point squircle with a soft shadow.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28,
                      color: CGColor(gray: 0, alpha: 0.35))
    context.addPath(bodyPath)
    context.setFillColor(CGColor(gray: 0.1, alpha: 1))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(bodyPath)
    context.clip()
    let background = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                colors: [CGColor(srgbRed: 0.20, green: 0.20, blue: 0.215, alpha: 1),
                                         CGColor(srgbRed: 0.075, green: 0.075, blue: 0.085, alpha: 1)] as CFArray,
                                locations: [0, 1])!
    context.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    context.restoreGState()

    // Thermometer: glass stem and bulb.
    let center = CGPoint(x: 472, y: 340)
    let stem = CGRect(x: center.x - 74, y: center.y, width: 148, height: 450)
    context.setFillColor(glass)
    context.addPath(CGPath(roundedRect: stem, cornerWidth: 74, cornerHeight: 74, transform: nil))
    context.addEllipse(in: CGRect(x: center.x - 128, y: center.y - 128, width: 256, height: 256))
    context.fillPath()

    // Inner channel.
    let inner = stem.insetBy(dx: 34, dy: 34)
    context.setFillColor(channel)
    context.addPath(CGPath(roundedRect: CGRect(x: inner.minX, y: center.y, width: inner.width, height: inner.maxY - center.y),
                           cornerWidth: inner.width / 2, cornerHeight: inner.width / 2, transform: nil))
    context.fillPath()

    // Accent fill: bulb plus mercury column.
    context.setFillColor(accent)
    context.addEllipse(in: CGRect(x: center.x - 88, y: center.y - 88, width: 176, height: 176))
    context.addPath(CGPath(roundedRect: CGRect(x: inner.minX, y: center.y, width: inner.width, height: 250),
                           cornerWidth: inner.width / 2, cornerHeight: inner.width / 2, transform: nil))
    context.fillPath()

    // Scale ticks to the right of the stem.
    context.setStrokeColor(CGColor(gray: 1, alpha: 0.55))
    context.setLineCap(.round)
    for (index, y) in [480.0, 570.0, 660.0, 750.0].enumerated() {
        context.setLineWidth(22)
        let length: CGFloat = index % 2 == 0 ? 120 : 76
        context.move(to: CGPoint(x: stem.maxX + 56, y: y))
        context.addLine(to: CGPoint(x: stem.maxX + 56 + length, y: y))
        context.strokePath()
    }
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    let context = graphics.cgContext
    context.interpolationQuality = .high
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    drawIcon(in: context)
    graphics.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try render(pixels: size).write(to: output.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(pixels: size * 2).write(to: output.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
print("Wrote \(output.path)")
