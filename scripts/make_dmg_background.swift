// Renders the DMG window background (660×400 pt, @2x) — dark glassy gradient, two "slots" and an arrow.
// Usage: swift scripts/make_dmg_background.swift Assets/dmg
import AppKit

let W: CGFloat = 660, H: CGFloat = 400
func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let g = ctx.cgContext
    // rep.size already maps points → pixels; no extra scale needed

    // background gradient
    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [NSColor(red: 0.13, green: 0.14, blue: 0.18, alpha: 1).cgColor,
                                 NSColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
    g.drawLinearGradient(bg, start: CGPoint(x: 0, y: H), end: CGPoint(x: W, y: 0), options: [])
    // soft accent glows
    for (c, p, r) in [(NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 0.18), CGPoint(x: 150, y: 260), 220.0),
                      (NSColor(red: 0.45, green: 0.60, blue: 1.00, alpha: 0.14), CGPoint(x: 520, y: 120), 240.0)] {
        let gl = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [c.cgColor, c.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
        g.drawRadialGradient(gl, startCenter: p, startRadius: 0, endCenter: p, endRadius: r, options: [])
    }

    // icon slots (centres must match the positions set in the DMG's .DS_Store)
    let left = CGPoint(x: 180, y: 200), right = CGPoint(x: 480, y: 200)
    for c in [left, right] {
        let ring = CGRect(x: c.x - 72, y: c.y - 72, width: 144, height: 144)
        g.setStrokeColor(NSColor.white.withAlphaComponent(0.10).cgColor); g.setLineWidth(1.5)
        g.strokeEllipse(in: ring)
    }
    // arrow
    g.setStrokeColor(NSColor.white.withAlphaComponent(0.75).cgColor)
    g.setLineWidth(5); g.setLineCap(.round); g.setLineJoin(.round)
    g.move(to: CGPoint(x: 268, y: 200)); g.addLine(to: CGPoint(x: 392, y: 200)); g.strokePath()
    g.move(to: CGPoint(x: 370, y: 222)); g.addLine(to: CGPoint(x: 394, y: 200)); g.addLine(to: CGPoint(x: 370, y: 178)); g.strokePath()

    // labels
    let para = NSMutableParagraphStyle(); para.alignment = .center
    func text(_ s: String, _ pt: CGPoint, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat) {
        let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                .foregroundColor: NSColor.white.withAlphaComponent(alpha), .paragraphStyle: para]
        let str = NSAttributedString(string: s, attributes: a)
        let sz = str.size()
        str.draw(in: CGRect(x: pt.x - 150, y: pt.y - sz.height / 2, width: 300, height: sz.height))
    }
    text("TokenBar", CGPoint(x: W / 2, y: 340), size: 26, weight: .bold, alpha: 0.95)
    text("Drag to Applications to install", CGPoint(x: W / 2, y: 308), size: 13, weight: .regular, alpha: 0.6)
    text("First launch: right-click → Open, or run the one-liner in README", CGPoint(x: W / 2, y: 46), size: 11, weight: .regular, alpha: 0.4)
    NSGraphicsContext.current = nil
    return rep
}
let out = URL(fileURLWithPath: CommandLine.arguments[1])
try! render(scale: 1).representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("background.png"))
try! render(scale: 2).representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("background@2x.png"))
print("wrote background.png + @2x")
