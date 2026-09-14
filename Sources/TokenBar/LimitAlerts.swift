import Foundation
import AppKit
import UserNotifications

/// Notifies when any rate-limit window crosses a threshold. One alert per (provider, limit, threshold, reset cycle).
@MainActor
final class LimitAlerts: ObservableObject {
    /// First warning threshold (0 = off). A second, fixed alert fires at `criticalPercent`.
    @Published var warnPercent: Int = UserDefaults.standard.object(forKey: "limit.warn") as? Int ?? 80 {
        didSet { UserDefaults.standard.set(warnPercent, forKey: "limit.warn") }
    }
    static let criticalPercent = 95

    private var fired = Set<String>()
    private static let canNotify = Bundle.main.bundleIdentifier != nil

    struct Worst { let provider: Provider; let limit: RateLimit }

    /// Highest-utilisation limit across providers (drives the menu-bar colour).
    private(set) var worst: Worst?

    func update(_ all: [Provider: ProviderLimits]) {
        self.all = all
        var w: Worst?
        for (p, pl) in all {
            for l in pl.limits {
                if w == nil || l.percent > w!.limit.percent { w = Worst(provider: p, limit: l) }
                check(p, l)
            }
        }
        worst = w
    }

    private var all: [Provider: ProviderLimits] = [:]

    /// Worst limit for one provider (or overall when nil).
    func worst(for p: Provider?) -> Worst? {
        guard let p else { return worst }
        return all[p]?.limits.max(by: { $0.percent < $1.percent }).map { Worst(provider: p, limit: $0) }
    }

    /// Menu-bar severity: 0 normal, 1 warn, 2 critical.
    func severity(for p: Provider? = nil) -> Int {
        guard let w = worst(for: p) else { return 0 }
        if Int(w.limit.percent) >= Self.criticalPercent { return 2 }
        if warnPercent > 0, Int(w.limit.percent) >= warnPercent { return 1 }
        return 0
    }
    var severity: Int { severity(for: nil) }

    private func check(_ p: Provider, _ l: RateLimit) {
        let cycle = l.resetsAt.map { String(Int($0.timeIntervalSince1970)) } ?? "none"
        var thresholds: [Int] = [Self.criticalPercent]
        if warnPercent > 0 { thresholds.append(warnPercent) }
        for t in thresholds.sorted(by: >) where Int(l.percent) >= t {
            let key = "\(p.rawValue)|\(l.key)|\(t)|\(cycle)"
            if fired.contains(key) { continue }
            fired.insert(key)
            // Only the highest crossed threshold notifies (avoid 80% + 95% back-to-back).
            notify(p, l, threshold: t)
            break
        }
        if fired.count > 500 { fired.removeAll() }
    }

    private func notify(_ p: Provider, _ l: RateLimit, threshold: Int) {
        guard Self.canNotify else { return }
        let c = UNMutableNotificationContent()
        c.title = threshold >= Self.criticalPercent
            ? L("limit.critical %@ %@", p.displayName, l.name)
            : L("limit.warn %@ %@ %d", p.displayName, l.name, Int(l.percent))
        c.body = l.resetText.isEmpty
            ? L("limit.body %d", Int(l.percent))
            : L("limit.body %d %@", Int(l.percent), l.resetText)
        c.sound = threshold >= Self.criticalPercent ? .defaultCritical : .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "tokenbar.limit.\(p.rawValue).\(l.key)", content: c, trigger: nil))
    }
}

/// Menu-bar icon variants: template (normal) or colour-baked (warn / critical).
enum MenuBarIconTint {
    private static var cache: [String: NSImage] = [:]

    /// Menu-bar image for the app (provider nil) or a provider logo, tinted when severity > 0.
    static func image(provider: Provider?, severity: Int) -> NSImage {
        let base: NSImage = provider.flatMap { ProviderLogo.image(for: $0) }.map { logo in
            let sized = logo.copy() as! NSImage
            sized.size = NSSize(width: 16, height: 16)
            sized.isTemplate = true
            return sized
        } ?? MenuBarIcon.image
        guard severity > 0 else { return base }
        let key = "\(provider?.rawValue ?? "app")|\(severity)"
        if let c = cache[key] { return c }
        let color: NSColor = severity >= 2
            ? NSColor(red: 1.0, green: 0.35, blue: 0.35, alpha: 1)
            : NSColor(red: 1.0, green: 0.72, blue: 0.30, alpha: 1)
        let img = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        img.isTemplate = false
        cache[key] = img
        return img
    }
}

/// Composes the single menu-bar image: provider/app icon (+ optional flame frame). MenuBarExtra labels
/// only carry one image, so anything animated has to be baked into it.
enum MenuBarComposer {
    private static func tinted(_ template: NSImage, _ color: NSColor) -> NSImage {
        let out = NSImage(size: template.size, flipped: false) { rect in
            template.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        out.isTemplate = false
        return out
    }

    static func image(provider: Provider?, severity: Int, flameStage: Int, flameFrame: Int) -> NSImage {
        let base = MenuBarIconTint.image(provider: provider, severity: severity)
        guard flameStage >= 1 else { return base }
        let flame = FlameSprite.frames(stage: flameStage)[flameFrame % FlameSprite.frameCount]
        // Flame engulfs the icon: drawn larger behind it, icon on top so the tongues show around the edges.
        let size = NSSize(width: 24, height: 20)
        let grow: CGFloat = [1.0, 1.05, 1.15, 1.25, 1.35][min(flameStage, 4)]
        // Tint the template icon into its own image first (sourceAtop on the composite would also paint the flame).
        let appearance = NSApp?.effectiveAppearance ?? NSAppearance.currentDrawing()
        let inkColor = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor.white : NSColor.black
        let icon: NSImage = base.isTemplate ? tinted(base, inkColor.withAlphaComponent(0.95)) : base
        let img = NSImage(size: size, flipped: false) { rect in
            let fw = min(16 * grow, rect.width), fh = min(18 * grow, rect.height + 2)
            flame.draw(in: NSRect(x: (rect.width - fw) / 2, y: -1.5, width: fw, height: fh))
            let iconSize: CGFloat = 12
            icon.draw(in: NSRect(x: (rect.width - iconSize) / 2, y: 1.5, width: iconSize, height: iconSize))
            return true
        }
        img.isTemplate = false
        return img
    }
}
