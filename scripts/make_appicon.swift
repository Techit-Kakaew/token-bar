// Renders AppIcon.icns: dark squircle, hexagon token outline, three rising bars in provider colours.
// Usage: swift scripts/make_appicon.swift <outdir>
import AppKit

func squircle(in r: CGRect) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: r.width * 0.2237, cornerHeight: r.height * 0.2237, transform: nil)
}

func render(px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let g = ctx.cgContext
    let S = CGFloat(px)
    // macOS icon grid: artwork occupies ~80% of canvas
    let inset = S * 0.1
    let box = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)

    // shadow
    g.saveGState()
    g.setShadow(offset: CGSize(width: 0, height: -S * 0.012), blur: S * 0.03, color: NSColor.black.withAlphaComponent(0.45).cgColor)
    g.addPath(squircle(in: box)); g.setFillColor(NSColor.black.cgColor); g.fillPath()
    g.restoreGState()

    // background gradient
    g.saveGState()
    g.addPath(squircle(in: box)); g.clip()
    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [NSColor(red: 0.16, green: 0.17, blue: 0.22, alpha: 1).cgColor,
                                 NSColor(red: 0.07, green: 0.07, blue: 0.10, alpha: 1).cgColor] as CFArray,
                        locations: [0, 1])!
    g.drawLinearGradient(bg, start: CGPoint(x: box.minX, y: box.maxY), end: CGPoint(x: box.maxX, y: box.minY), options: [])
    // subtle top highlight
    let hl = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [NSColor.white.withAlphaComponent(0.10).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
                        locations: [0, 1])!
    g.drawLinearGradient(hl, start: CGPoint(x: box.midX, y: box.maxY), end: CGPoint(x: box.midX, y: box.midY), options: [])
    g.restoreGState()

    // hexagon outline
    let c = CGPoint(x: S / 2, y: S / 2)
    let r = box.width * 0.36
    let hex = CGMutablePath()
    for i in 0..<6 {
        let a = CGFloat(i) * .pi / 3 + .pi / 6
        let p = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
        i == 0 ? hex.move(to: p) : hex.addLine(to: p)
    }
    hex.closeSubpath()
    g.setLineWidth(S * 0.035); g.setLineJoin(.round)
    g.setStrokeColor(NSColor.white.withAlphaComponent(0.85).cgColor)
    g.addPath(hex); g.strokePath()

    // bars: terracotta (Claude), mint (Codex), periwinkle (Gemini)
    let colors: [NSColor] = [
        NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1),
        NSColor(red: 0.30, green: 0.85, blue: 0.65, alpha: 1),
        NSColor(red: 0.45, green: 0.60, blue: 1.00, alpha: 1),
    ]
    let barW = S * 0.10, gap = S * 0.05
    let heights: [CGFloat] = [S * 0.16, S * 0.26, S * 0.36]
    let totalW = barW * 3 + gap * 2
    var x = c.x - totalW / 2
    let baseY = c.y - S * 0.18
    for (i, h) in heights.enumerated() {
        let rect = CGRect(x: x, y: baseY, width: barW, height: h)
        g.setFillColor(colors[i].cgColor)
        g.addPath(CGPath(roundedRect: rect, cornerWidth: barW * 0.3, cornerHeight: barW * 0.3, transform: nil))
        g.fillPath()
        x += barW + gap
    }
    NSGraphicsContext.current = nil
    return rep
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = out.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    let rep = render(px: px)
    try! rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent("icon_\(name).png"))
}
try! render(px: 1024).representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("AppIcon-1024.png"))
print("iconset written to \(iconset.path)")
