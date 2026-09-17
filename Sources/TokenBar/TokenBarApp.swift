import SwiftUI
import UserNotifications


struct TokenBarApp: App {
    @StateObject private var store = UsageStore()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        let _ = { AppDelegate.onUpdateTapped = { [store] in Task { @MainActor in await store.updates.installUpdate() } } }()
        MenuBarExtra {
            PopoverView().environmentObject(store)
        } label: {
            let focus = store.menuBarProvider
            let sev = store.alerts.severity(for: focus)
            // MenuBarExtra labels carry ONE image + ONE text, so tokens and limit % are joined into one string.
            let composed = MenuBarIconTint.image(provider: focus, severity: sev)
            let text = menuBarText(focus: focus, severity: sev)
            HStack(spacing: 4) {
                if composed.isTemplate {
                    Image(nsImage: composed).renderingMode(.template)
                } else {
                    Image(nsImage: composed).renderingMode(.original)
                }
                if !text.isEmpty {
                    Text(text).font(.system(size: 11, weight: .medium, design: .rounded)).monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)

        SwiftUI.Window("TokenBar Dashboard", id: "dashboard") {
            DashboardView().environmentObject(store)
        }
        .defaultSize(width: 980, height: 680)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
    }
}

extension TokenBarApp {
    /// Tokens (if enabled) plus the worst limit percentage while over threshold.
    func menuBarText(focus: Provider?, severity: Int) -> String {
        var text = store.showNumberInBar ? store.menuBarTokens.compact : ""
        if severity > 0, let w = store.alerts.worst(for: focus) {
            text += (text.isEmpty ? "" : " · ") + "\(Int(w.limit.percent))%"
        }
        return text
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Set by the App so a tapped update notification can start the install.
    static var onUpdateTapped: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // no Dock icon even when run from `swift run`
        if Bundle.main.bundleIdentifier != nil { UNUserNotificationCenter.current().delegate = self }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if response.notification.request.identifier == UpdateChecker.notificationId {
            await MainActor.run { Self.onUpdateTapped?() }
        }
    }

    /// Show our notifications even while the popover is frontmost.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}

/// Menu-bar template icon, drawn as vectors at render time so it is crisp at every scale
/// (loading the 1× PNG and scaling it blurred on Retina). Same shape as scripts/make_icon.swift.
enum MenuBarIcon {
    /// Kept for --icon diagnostics and the resource-bundle lookup used by ProviderLogo.
    static let url: URL? = {
        if let res = Bundle.main.resourceURL,
           let b = Bundle(url: res.appendingPathComponent("TokenBar_TokenBar.bundle")),
           let u = b.url(forResource: "MenuBarIcon", withExtension: "png") { return u }
        let exe = Bundle.main.executableURL?.deletingLastPathComponent()
        if let b = exe.flatMap({ Bundle(url: $0.appendingPathComponent("TokenBar_TokenBar.bundle")) }),
           let u = b.url(forResource: "MenuBarIcon", withExtension: "png") { return u }
        return nil
    }()

    static let image: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { rect in
            guard let g = NSGraphicsContext.current?.cgContext else { return false }
            g.setShouldAntialias(true)
            g.setStrokeColor(NSColor.black.cgColor)
            g.setFillColor(NSColor.black.cgColor)
            let s = rect.width
            let c = CGPoint(x: rect.midX, y: rect.midY)
            // hexagon outline (pointy top)
            let r = s / 2 - 1.4
            let hex = CGMutablePath()
            for i in 0..<6 {
                let a = CGFloat(i) * .pi / 3 + .pi / 6
                let p = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
                i == 0 ? hex.move(to: p) : hex.addLine(to: p)
            }
            hex.closeSubpath()
            g.setLineWidth(1.6); g.setLineJoin(.round)
            g.addPath(hex); g.strokePath()
            // three rising bars
            let barW: CGFloat = 2.2, gap: CGFloat = 1.6
            let heights: [CGFloat] = [4, 6.5, 9]
            var x = c.x - (barW * 3 + gap * 2) / 2
            let baseY = c.y - 4.5
            for h in heights {
                g.addPath(CGPath(roundedRect: CGRect(x: x, y: baseY, width: barW, height: h), cornerWidth: 0.8, cornerHeight: 0.8, transform: nil))
                g.fillPath()
                x += barW + gap
            }
            return true
        }
        img.isTemplate = true
        return img
    }()
}

/// Small app-icon view for headers (the coloured AppIcon; falls back to the template menu-bar glyph).
struct AppIconView: View {
    var size: CGFloat = 18
    var body: some View {
        if Bundle.main.bundleIdentifier != nil, let icns = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: icns) {
            Image(nsImage: img).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            Image(nsImage: MenuBarIcon.image).renderingMode(.template).resizable().frame(width: size * 0.8, height: size * 0.8)
                .foregroundStyle(.secondary)
        }
    }
}

/// Vendor logos (SVG, template-tinted) from Resources/logos. Falls back to SF Symbols.
enum ProviderLogo {
    private static var cache: [Provider: NSImage] = [:]

    static func image(for p: Provider) -> NSImage? {
        if let c = cache[p] { return c }
        guard let dir = MenuBarIcon.url?.deletingLastPathComponent() else { return nil }
        let url = dir.appendingPathComponent("\(p.logoFile).svg")
        guard let img = NSImage(contentsOf: url) else { return nil }
        img.isTemplate = true
        cache[p] = img
        return img
    }
}

struct ProviderLogoView: View {
    let provider: Provider
    var size: CGFloat = 12
    var body: some View {
        if let img = ProviderLogo.image(for: provider) {
            Image(nsImage: img).renderingMode(.template).resizable().scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: provider.symbol).font(.system(size: size, weight: .bold))
        }
    }
}

/// Hands the App's `openWindow` action to the store so a global hotkey can open the dashboard.
private struct DashboardOpener: View {
    let store: UsageStore
    @Environment(\.openWindow) private var openWindow
    var body: some View { Color.clear.onAppear { store.openDashboard = { openWindow(id: "dashboard") } } }
}
