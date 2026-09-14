import Foundation
import SwiftUI

if CommandLine.arguments.contains("--icon") {
    print("icon:", MenuBarIcon.url?.path ?? "FALLBACK (SF Symbol)", "template=\(MenuBarIcon.image.isTemplate)")
    exit(0)
}

if let i = CommandLine.arguments.firstIndex(of: "--export"), i + 1 < CommandLine.arguments.count {
    // Headless export for scripts/cron: TokenBar --export events|daily|report [today|7d|30d|all] > file
    let kind = CommandLine.arguments[i + 1]
    let winArg = i + 2 < CommandLine.arguments.count ? CommandLine.arguments[i + 2].lowercased() : "30d"
    let window: Window = ["today": .today, "7d": .week, "30d": .month, "all": .all][winArg] ?? .month
    Task { @MainActor in
        let store = UsageStore()
        while store.lastRefresh == nil { try? await Task.sleep(for: .milliseconds(100)) }
        if kind == "report" { try? await Task.sleep(for: .seconds(2)) } // give Claude limits a moment
        let out: String
        switch kind {
        case "events": out = Exporter.eventsCSV(store.recentEvents.filter { window.contains($0.timestamp) })
        case "daily": out = Exporter.dailyCSV(store.stats)
        case "report": out = Exporter.markdown(stats: store.stats, window: window, limits: store.limits)
        default: FileHandle.standardError.write("unknown export kind: \(kind)\n".data(using: .utf8)!); exit(2)
        }
        print(out, terminator: "")
        exit(0)
    }
    RunLoop.main.run()
}

if let i = CommandLine.arguments.firstIndex(of: "--flame-preview"), i + 1 < CommandLine.arguments.count {
    let out = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    let scale: CGFloat = 4, cell: CGFloat = 20 * scale
    let stages = [1, 2, 3, 4]
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(cell) * FlameSprite.frameCount, pixelsHigh: Int(cell) * stages.count,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor(white: 0.12, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh).fill()
    for (row, st) in stages.enumerated() {
        for (f, img) in FlameSprite.frames(stage: st).enumerated() {
            img.draw(in: NSRect(x: CGFloat(f) * cell + 2 * scale, y: CGFloat(row) * cell + scale, width: 16 * scale, height: 18 * scale))
        }
    }
    try? rep.representation(using: .png, properties: [:])!.write(to: out)
    print("wrote \(out.path)"); exit(0)
}

if CommandLine.arguments.contains("--notify-test") {
    // Must run from the installed .app bundle: /Applications/TokenBar.app/Contents/MacOS/TokenBar --notify-test
    Task { @MainActor in
        let r = BreakReminder()
        r.requestPermission()
        try? await Task.sleep(for: .seconds(1))
        r.fireTest()
        try? await Task.sleep(for: .seconds(2))
        print("test notification sent (bundle: \(Bundle.main.bundleIdentifier ?? "none"))")
        exit(0)
    }
    RunLoop.main.run()
}

if CommandLine.arguments.contains("--streak") {
    let sources: [UsageSource] = [ClaudeSource(), CodexSource(), GeminiSource(), ZedSource(), OpenCodeSource(), GeminiSource(provider: .qwen, dir: ".qwen")]
    let dayAgo = Date().addingTimeInterval(-86400)
    let ts = sources.flatMap { src in src.enumerateFiles().flatMap { src.parse(file: $0) } }.map(\.timestamp).filter { $0 > dayAgo }
    for gap in [10, 15, 30] {
        if let s = BreakReminder.computeStreak(ts, idleGap: TimeInterval(gap * 60)) {
            print("gap=\(gap)m streak start=\(s.start) last=\(s.last) duration=\(Int(s.duration / 60))m")
        } else { print("gap=\(gap)m no active streak") }
    }
    // synthetic check: 3 events 5 min apart then 40 min gap then 1 event → streak = last only
    let now = Date()
    let synth = [now, now.addingTimeInterval(-2400), now.addingTimeInterval(-2700), now.addingTimeInterval(-3000)]
    let s = BreakReminder.computeStreak(synth, idleGap: 900, now: now)!
    print("synthetic: duration=\(Int(s.duration / 60))m (expect 0)")
    let s2 = BreakReminder.computeStreak(synth, idleGap: 3000, now: now)!
    print("synthetic wide gap: duration=\(Int(s2.duration / 60))m (expect 50)")
    exit(0)
}

if CommandLine.arguments.contains("--dump") {
    // Debug: print aggregated usage as text and exit.
    let sources: [UsageSource] = [ClaudeSource(), CodexSource(), GeminiSource(), ZedSource(), OpenCodeSource(), GeminiSource(provider: .qwen, dir: ".qwen")]
    for src in sources {
        let files = src.enumerateFiles()
        let events = files.flatMap { src.parse(file: $0) }
        var byWin: [Window: TokenBreakdown] = [:]
        var models: [String: TokenBreakdown] = [:]
        for e in events {
            let c = Pricing.cost(e)
            for w in Window.allCases where w.contains(e.timestamp) { byWin[w, default: TokenBreakdown()].add(e, cost: c) }
            models[e.model, default: TokenBreakdown()].add(e, cost: c)
        }
        print("== \(src.provider.displayName)  available=\(src.isAvailable) files=\(files.count) events=\(events.count)")
        for w in Window.allCases {
            let b = byWin[w] ?? TokenBreakdown()
            print(String(format: "  %-6@ total=%@ in=%@ out=%@ cr=%@ cw=%@ cost=%@ calls=%d",
                         w.rawValue as NSString, b.total.compact as NSString, b.input.compact as NSString, b.output.compact as NSString,
                         b.cacheRead.compact as NSString, b.cacheWrite.compact as NSString, b.cost.usd as NSString, b.calls))
        }
        for (m, b) in models.sorted(by: { $0.value.cost > $1.value.cost }).prefix(8) {
            print("    \(m): \(b.total.compact) \(b.cost.usd) price=\(Pricing.price(for: m) != nil)")
        }
    }
    exit(0)
}

if let i = CommandLine.arguments.firstIndex(of: "--snapshot-dashboard"), i + 1 < CommandLine.arguments.count {
    let out = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    Task { @MainActor in
        let store = UsageStore()
        if let lang = ProcessInfo.processInfo.environment["TOKENBAR_SNAPSHOT_LANG"] { L10n.current = L10n.resolve(override: lang) }
        while store.lastRefresh == nil { try? await Task.sleep(for: .milliseconds(100)) }
        try? await Task.sleep(for: .milliseconds(300))
        let light = ProcessInfo.processInfo.environment["TOKENBAR_SNAPSHOT_SCHEME"] == "light"
        let view = DashboardView().environmentObject(store).frame(width: 980)
            .background(light ? Color(red: 0.95, green: 0.95, blue: 0.97) : Color(red: 0.08, green: 0.08, blue: 0.10))
            .environment(\.colorScheme, light ? .light : .dark).environment(\.isSnapshot, true)
        let r = ImageRenderer(content: view); r.scale = 2
        if let img = r.nsImage, let tiff = img.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: out); print("wrote \(out.path)")
        } else { print("render failed") }
        exit(0)
    }
    RunLoop.main.run()
}

if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
    // Debug: render the popover to a PNG (no window/permissions needed).
    let out = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    Task { @MainActor in
        let store = UsageStore()
        if let lang = ProcessInfo.processInfo.environment["TOKENBAR_SNAPSHOT_LANG"] { L10n.current = L10n.resolve(override: lang) }
        while store.lastRefresh == nil { try? await Task.sleep(for: .milliseconds(100)) }
        try? await Task.sleep(for: .milliseconds(300))
        let light = ProcessInfo.processInfo.environment["TOKENBAR_SNAPSHOT_SCHEME"] == "light"
        let view = PopoverView().environmentObject(store)
            .background(light ? Color(red: 0.93, green: 0.93, blue: 0.95) : Color(red: 0.11, green: 0.11, blue: 0.13))
            .environment(\.colorScheme, light ? .light : .dark)
            .environment(\.isSnapshot, true)
        let r = ImageRenderer(content: view)
        r.scale = 2
        if let img = r.nsImage, let tiff = img.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: out)
            print("wrote \(out.path)")
        } else { print("render failed") }
        exit(0)
    }
    RunLoop.main.run()
}

TokenBarApp.main()
