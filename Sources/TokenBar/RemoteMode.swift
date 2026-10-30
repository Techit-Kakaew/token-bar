import AppKit
import SwiftUI
import IOKit.pwr_mgt
import LocalAuthentication
import UserNotifications

/// "Remote mode": keep the Mac awake (screen may still dim) and cover every display with an animated
/// overlay so the machine can be driven from the phone. Session-only — never persisted across launches.
@MainActor
final class RemoteMode: ObservableObject {
    @Published private(set) var isOn = false
    @Published var overlayText: String = UserDefaults.standard.string(forKey: "remote.text") ?? "Claude is running" {
        didSet { UserDefaults.standard.set(overlayText, forKey: "remote.text"); overlays.forEach { $0.refresh() } }
    }
    @Published var subtitleMode: String = UserDefaults.standard.string(forKey: "remote.subtitle") ?? "sessions" {   // sessions | clock | none
        didSet { UserDefaults.standard.set(subtitleMode, forKey: "remote.subtitle") }
    }
    /// Minutes without any live session before remote mode switches itself off (0 = never).
    @Published var autoOffMinutes: Int = UserDefaults.standard.object(forKey: "remote.autoOff") as? Int ?? 60 {
        didSet { UserDefaults.standard.set(autoOffMinutes, forKey: "remote.autoOff") }
    }
    @Published var showOverlay: Bool = UserDefaults.standard.object(forKey: "remote.overlay") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showOverlay, forKey: "remote.overlay"); if isOn { showOverlay ? presentOverlays() : dismissOverlays() } }
    }

    private var assertion: IOPMAssertionID = 0
    private var overlays: [OverlayWindow] = []
    private var idleSince: Date?
    private var screenObserver: Any?
    var liveSessionProvider: () -> [LiveSession] = { [] }

    // MARK: toggle

    func turnOn() {
        guard !isOn else { return }
        var id: IOPMAssertionID = 0
        let ok = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                             IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                             "TokenBar remote mode" as CFString, &id)
        if ok == kIOReturnSuccess { assertion = id }
        isOn = true
        idleSince = nil
        if showOverlay { presentOverlays() }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in if self?.isOn == true, self?.showOverlay == true { self?.presentOverlays() } }
        }
    }

    func turnOff(reason: String? = nil) {
        guard isOn else { return }
        if assertion != 0 { IOPMAssertionRelease(assertion); assertion = 0 }
        dismissOverlays()
        if let o = screenObserver { NotificationCenter.default.removeObserver(o); screenObserver = nil }
        isOn = false
        if let reason, Bundle.main.bundleIdentifier != nil {
            let c = UNMutableNotificationContent(); c.title = L("remote.off.title"); c.body = reason
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "tokenbar.remote.off", content: c, trigger: nil))
        }
    }

    /// Unlock = Touch ID / password via LocalAuthentication, then turn off. Returns false if auth failed.
    func unlock() async -> Bool {
        let ctx = LAContext()
        ctx.localizedReason = L("remote.unlock.reason")
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { turnOff(); return true }   // no auth available → just exit
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: L("remote.unlock.reason"))
            if ok { turnOff() }
            return ok
        } catch { return false }
    }

    /// Called on every store refresh: auto-off when idle too long.
    func tick(liveSessions: [LiveSession]) {
        guard isOn else { return }
        overlays.forEach { $0.refresh() }
        guard autoOffMinutes > 0 else { return }
        if liveSessions.isEmpty {
            if idleSince == nil { idleSince = Date() }
            if let s = idleSince, Date().timeIntervalSince(s) > Double(autoOffMinutes) * 60 {
                turnOff(reason: L("remote.off.idle %d", autoOffMinutes))
            }
        } else { idleSince = nil }
    }

    var onBattery: Bool {
        !(ProcessInfo.processInfo.isLowPowerModeEnabled == false && Self.isPluggedIn())
    }
    private static func isPluggedIn() -> Bool {
        // IOPSCopyPowerSourcesInfo without linking IOKit.ps: shell out to pmset is overkill; use the AC-power notification key instead.
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset"); p.arguments = ["-g", "batt"]
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        guard (try? p.run()) != nil else { return true }
        p.waitUntilExit()
        let s = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return s.contains("AC Power")
    }

    // MARK: overlays

    private func presentOverlays() {
        dismissOverlays()
        for screen in NSScreen.screens {
            let w = OverlayWindow(screen: screen, mode: self)
            w.orderFrontRegardless()
            overlays.append(w)
        }
        overlays.first?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func dismissOverlays() {
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
    }
}

/// Borderless full-screen window above everything, on every Space; hosts the SwiftUI overlay.
/// Built with the 4-argument designated initializer (the `screen:` variant chains into it, and a Swift
/// subclass that doesn't override it traps), then positioned onto the target screen.
final class OverlayWindow: NSWindow {
    private var host: NSHostingView<OverlayView>?
    private weak var mode: RemoteMode?

    convenience init(screen: NSScreen, mode: RemoteMode) {
        self.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        self.mode = mode
        let h = NSHostingView(rootView: OverlayView(mode: mode))
        host = h
        contentView = h
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = true
        backgroundColor = .black
        ignoresMouseEvents = false
        hasShadow = false
        isReleasedWhenClosed = false
        setFrame(screen.frame, display: true)
    }

    override var canBecomeKey: Bool { true }
    func refresh() { if let mode { host?.rootView = OverlayView(mode: mode) } }

    /// Any key/click → prompt to unlock (never a silent dismiss).
    override func keyDown(with event: NSEvent) { Task { await mode?.unlock() } }
    override func mouseDown(with event: NSEvent) { Task { await mode?.unlock() } }
}

/// Animated centre text: slow breathing glow + gradient sweep, subtitle with live-session count or clock.
struct OverlayView: View {
    @ObservedObject var mode: RemoteMode

    var body: some View {
        ZStack {
            Color.black
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                ZStack {
                    // drifting glow blobs
                    ForEach(0..<3, id: \.self) { i in
                        let ph = Double(i) * 2.1
                        Circle()
                            .fill(blobColor(i).opacity(0.18))
                            .frame(width: 700, height: 700)
                            .blur(radius: 160)
                            .offset(x: CGFloat(sin(t * 0.11 + ph)) * 320, y: CGFloat(cos(t * 0.09 + ph)) * 180)
                    }
                    VStack(spacing: 18) {
                        AppIconView(size: 56).opacity(0.9)
                        Text(mode.overlayText)
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(colors: [.white, Color(red: 0.95, green: 0.78, blue: 0.62), .white],
                                               startPoint: UnitPoint(x: (sin(t * 0.5) + 1) / 2 - 0.5, y: 0),
                                               endPoint: UnitPoint(x: (sin(t * 0.5) + 1) / 2 + 0.5, y: 1)))
                            .shadow(color: Color(red: 0.85, green: 0.47, blue: 0.34).opacity(0.35 + 0.15 * sin(t * 1.2)), radius: 30)
                            .scaleEffect(1 + 0.012 * sin(t * 1.2))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 80)
                        subtitle(t)
                    }
                }
            }
            VStack {
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "touchid").font(.system(size: 12))
                    Text(L("remote.hint")).font(.system(size: 12))
                }
                .foregroundStyle(.white.opacity(0.35))
                .padding(.bottom, 36)
            }
        }
        .ignoresSafeArea()
    }

    private func blobColor(_ i: Int) -> Color {
        [Color(red: 0.85, green: 0.47, blue: 0.34), Color(red: 0.30, green: 0.85, blue: 0.65), Color(red: 0.45, green: 0.60, blue: 1.0)][i]
    }

    @ViewBuilder
    private func subtitle(_ t: Double) -> some View {
        let live = mode.liveSessionProvider()
        switch mode.subtitleMode {
        case "clock":
            Text(Date(), style: .time).font(.system(size: 22, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.5))
        case "none":
            EmptyView()
        default:
            HStack(spacing: 8) {
                Circle().fill(live.isEmpty ? .gray : .green).frame(width: 8, height: 8)
                    .opacity(live.isEmpty ? 0.6 : 0.6 + 0.4 * sin(t * 3))
                Text(live.isEmpty ? L("remote.sub.idle") : L("remote.sub.live %d", live.count))
                    .font(.system(size: 20, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.55))
            }
        }
    }
}
