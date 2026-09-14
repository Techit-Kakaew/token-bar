import AppKit

/// Procedurally drawn flame frames for the menu bar (SwiftUI animations don't run inside a status item).
enum FlameSprite {
    static let frameCount = 8
    private static var cache: [Int: [NSImage]] = [:]

    /// `stage` 2 = warming (orange), 3 = hot, 4 = blaze (red). Frames loop.
    static func frames(stage: Int) -> [NSImage] {
        if let c = cache[stage] { return c }
        let imgs = (0..<frameCount).map { draw(frame: $0, stage: stage) }
        cache[stage] = imgs
        return imgs
    }

    private static func draw(frame: Int, stage: Int) -> NSImage {
        let size = NSSize(width: 16, height: 18)
        let img = NSImage(size: size, flipped: false) { rect in
            guard let g = NSGraphicsContext.current?.cgContext else { return false }
            let t = Double(frame) / Double(frameCount) * 2 * .pi
            let heat = [0, 0, 0.55, 0.8, 1.0][min(stage, 4)]
            let outer = stage >= 4 ? NSColor(red: 1.0, green: 0.30, blue: 0.22, alpha: 1) : NSColor(red: 1.0, green: 0.55, blue: 0.18, alpha: 1)
            let inner = NSColor(red: 1.0, green: 0.85, blue: 0.35, alpha: 1)
            let w = rect.width, h = rect.height
            let cx = w / 2
            // outer tongue
            g.saveGState()
            flamePath(cx: cx, base: 1.5, height: h * (0.78 + 0.12 * heat) * (0.92 + 0.08 * sin(t)),
                      width: w * 0.42 * (0.9 + 0.1 * cos(t * 1.3)), lean: CGFloat(sin(t)) * 1.6, tipWobble: CGFloat(sin(t * 2 + 1)) * 1.2)
                .addClip()
            g.drawLinearGradient(
                CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [outer.cgColor, outer.withAlphaComponent(0.85).blended(withFraction: 0.5, of: inner)!.cgColor] as CFArray,
                           locations: [0, 1])!,
                start: CGPoint(x: cx, y: 0), end: CGPoint(x: cx, y: h), options: [])
            g.restoreGState()
            // inner core
            g.saveGState()
            flamePath(cx: cx, base: 1.5, height: h * (0.42 + 0.08 * heat) * (0.9 + 0.1 * sin(t * 1.7 + 0.8)),
                      width: w * 0.2, lean: CGFloat(sin(t + 0.6)) * 0.8, tipWobble: CGFloat(cos(t * 2.3)) * 0.6)
                .addClip()
            inner.setFill(); rect.fill()
            g.restoreGState()
            return true
        }
        img.isTemplate = false
        return img
    }

    /// Teardrop flame: rounded base, wobbling tip.
    private static func flamePath(cx: CGFloat, base: CGFloat, height: CGFloat, width: CGFloat, lean: CGFloat, tipWobble: CGFloat) -> NSBezierPath {
        let p = NSBezierPath()
        let tip = CGPoint(x: cx + lean + tipWobble, y: base + height)
        let l = CGPoint(x: cx - width, y: base + height * 0.32)
        let r = CGPoint(x: cx + width, y: base + height * 0.32)
        p.move(to: CGPoint(x: cx, y: base))
        p.curve(to: l, controlPoint1: CGPoint(x: cx - width * 0.9, y: base), controlPoint2: CGPoint(x: cx - width * 1.05, y: base + height * 0.1))
        p.curve(to: tip, controlPoint1: CGPoint(x: cx - width * 0.9, y: base + height * 0.62), controlPoint2: CGPoint(x: cx + lean * 0.5 - width * 0.15, y: base + height * 0.9))
        p.curve(to: r, controlPoint1: CGPoint(x: cx + lean * 0.5 + width * 0.15, y: base + height * 0.9), controlPoint2: CGPoint(x: cx + width * 0.9, y: base + height * 0.62))
        p.curve(to: CGPoint(x: cx, y: base), controlPoint1: CGPoint(x: cx + width * 1.05, y: base + height * 0.1), controlPoint2: CGPoint(x: cx + width * 0.9, y: base))
        p.close()
        return p
    }
}
