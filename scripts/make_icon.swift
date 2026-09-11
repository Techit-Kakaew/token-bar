// Renders the menu-bar template icon: hexagon "token" outline with three rising bars.
// Usage: swift scripts/make_icon.swift <outdir>
import AppKit

func render(size: CGFloat, scale: CGFloat, to url: URL) {
    let px = Int(size * scale)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let g = ctx.cgContext
    g.scaleBy(x: scale, y: scale)
    g.setStrokeColor(NSColor.black.cgColor)
    g.setFillColor(NSColor.black.cgColor)

    // Hexagon (pointy top), inset for stroke
    let c = CGPoint(x: size / 2, y: size / 2)
    let r: CGFloat = size / 2 - 1.4
    let hex = CGMutablePath()
    for i in 0..<6 {
        let a = CGFloat(i) * .pi / 3 + .pi / 6
        let p = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
        i == 0 ? hex.move(to: p) : hex.addLine(to: p)
    }
    hex.closeSubpath()
    g.setLineWidth(1.6)
    g.setLineJoin(.round)
    g.addPath(hex)
    g.strokePath()

    // Three rising bars
    let barW: CGFloat = 2.2
    let gap: CGFloat = 1.6
    let heights: [CGFloat] = [4, 6.5, 9]
    let totalW = barW * 3 + gap * 2
    var x = c.x - totalW / 2
    let baseY = c.y - 4.5
    for h in heights {
        let rect = CGRect(x: x, y: baseY, width: barW, height: h)
        g.addPath(CGPath(roundedRect: rect, cornerWidth: 0.8, cornerHeight: 0.8, transform: nil))
        g.fillPath()
        x += barW + gap
    }

    NSGraphicsContext.current = nil
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("wrote \(url.lastPathComponent) \(px)px")
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
render(size: 18, scale: 1, to: out.appendingPathComponent("MenuBarIcon.png"))
render(size: 18, scale: 2, to: out.appendingPathComponent("MenuBarIcon@2x.png"))
render(size: 18, scale: 8, to: out.appendingPathComponent("MenuBarIcon-preview.png"))
