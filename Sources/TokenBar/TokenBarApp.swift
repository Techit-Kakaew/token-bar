import SwiftUI


struct TokenBarApp: App {
    @StateObject private var store = UsageStore()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        MenuBarExtra {
            PopoverView().environmentObject(store)
        } label: {
            let focus = store.menuBarProvider
            let sev = store.alerts.severity(for: focus)
            HStack(spacing: 4) {
                if sev > 0 {
                    Image(nsImage: MenuBarIconTint.image(provider: focus, severity: sev)).renderingMode(.original)
                } else {
                    Image(nsImage: MenuBarIconTint.image(provider: focus, severity: 0)).renderingMode(.template)
                }
                if let st = store.breaks.streak {
                    let lvl = st.duration / 60 / Double(max(store.breaks.thresholdMinutes, 1))
                    if lvl >= 0.5 {
                        Image(systemName: lvl >= 1 ? "flame.fill" : "flame")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(lvl >= 1 ? Color(red: 1.0, green: 0.35, blue: 0.25) : Color(red: 1.0, green: 0.6, blue: 0.2))
                    }
                }
                if store.showNumberInBar {
                    Text(store.menuBarTokens.compact)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                }
                if sev > 0, let w = store.alerts.worst(for: focus) {
                    Text("· \(Int(w.limit.percent))%")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // no Dock icon even when run from `swift run`
    }
}

/// Custom template icon from Resources/MenuBarIcon(@2x).png. Falls back to an SF Symbol if missing.
enum MenuBarIcon {
    /// Resolved resource URL (nil → SF Symbol fallback).
    static let url: URL? = {
        // Hand-made .app: bundle lives in Contents/Resources. `swift run`: use Bundle.module.
        if let res = Bundle.main.resourceURL,
           let b = Bundle(url: res.appendingPathComponent("TokenBar_TokenBar.bundle")),
           let u = b.url(forResource: "MenuBarIcon", withExtension: "png") { return u }
        let fm = FileManager.default
        let exe = Bundle.main.executableURL?.deletingLastPathComponent()
        if let b = exe.flatMap({ Bundle(url: $0.appendingPathComponent("TokenBar_TokenBar.bundle")) }),
           let u = b.url(forResource: "MenuBarIcon", withExtension: "png"), fm.fileExists(atPath: u.path) { return u }
        return nil
    }()

    static let image: NSImage = {
        if let url, let img = NSImage(contentsOf: url) {
            img.isTemplate = true            // lets macOS tint for light/dark menu bar
            img.size = NSSize(width: 18, height: 18)
            return img
        }
        return NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: nil)!
    }()
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
