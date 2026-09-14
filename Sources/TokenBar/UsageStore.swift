import Foundation
import Combine
import SwiftUI
import AppKit

@MainActor
final class UsageStore: ObservableObject {
    @Published var stats: [Provider: ProviderStats] = [:]
    @Published var lastRefresh: Date?
    @Published var limits: [Provider: ProviderLimits] = [:]
    /// Raw events from the last 30 days (for per-day drill-down in the dashboard).
    @Published var recentEvents: [UsageEvent] = []
    let breaks = BreakReminder()
    let alerts = LimitAlerts()
    let updates = UpdateChecker()
    let budget = Budget()
    let hotkeys = HotKeys()

    /// Menu-bar animation style: "flame" (engulfing fire by stage) or a sprite sheet name ("cat", or a custom folder).
    @Published var menuBarAnimation: String = UserDefaults.standard.string(forKey: "menuBarAnimation") ?? "flame" {
        didSet { UserDefaults.standard.set(menuBarAnimation, forKey: "menuBarAnimation"); flameTimer?.invalidate(); flameTimer = nil; updateFlameTimer() }
    }
    /// Sprite mode: animate always (RunCat style, speed follows streak) or only while a streak is active.
    @Published var spriteAlwaysOn: Bool = UserDefaults.standard.object(forKey: "spriteAlwaysOn") as? Bool ?? true {
        didSet { UserDefaults.standard.set(spriteAlwaysOn, forKey: "spriteAlwaysOn"); flameTimer?.invalidate(); flameTimer = nil; updateFlameTimer() }
    }

    // Menu-bar animation frame counter; the timer runs only when something is animating.
    @Published var flameFrame = 0
    private var flameTimer: Timer?
    var streakLevel: Double {
        guard let s = breaks.streak else { return 0 }
        return s.duration / 60 / Double(max(breaks.thresholdMinutes, 1))
    }
    var flameStage: Int { let l = streakLevel; return l >= 1 ? 4 : l >= 0.75 ? 3 : l >= 0.5 ? 2 : l >= 0.25 ? 1 : 0 }
    private var currentInterval: TimeInterval = 0
    func updateFlameTimer() {
        let sprite = menuBarAnimation != "flame"
        let want = sprite ? (spriteAlwaysOn || streakLevel > 0) : flameStage >= 1
        let interval = sprite ? Sprites.interval(level: streakLevel) : 1.0 / 8
        if want {
            if flameTimer == nil || abs(interval - currentInterval) > 0.01 {
                flameTimer?.invalidate()
                currentInterval = interval
                flameTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self else { return }
                        self.flameFrame &+= 1
                    }
                }
            }
        } else if let t = flameTimer {
            t.invalidate(); flameTimer = nil; flameFrame = 0
        }
    }
    @Published var hotkeyPopover: String = UserDefaults.standard.string(forKey: "hotkey.popover") ?? "⌥⇧T" {
        didSet { UserDefaults.standard.set(hotkeyPopover, forKey: "hotkey.popover"); bindHotkeys() }
    }
    @Published var hotkeyDashboard: String = UserDefaults.standard.string(forKey: "hotkey.dashboard") ?? "Off" {
        didSet { UserDefaults.standard.set(hotkeyDashboard, forKey: "hotkey.dashboard"); bindHotkeys() }
    }
    /// Set by the App so the dashboard hotkey can open the window scene.
    var openDashboard: (() -> Void)?

    func bindHotkeys() {
        hotkeys.bind(id: 1, combo: .named(hotkeyPopover)) { HotKeys.toggleStatusItem() }
        hotkeys.bind(id: 2, combo: .named(hotkeyDashboard)) { [weak self] in self?.openDashboard?(); NSApp.activate(ignoringOtherApps: true) }
    }

    var todaySpend: Double { Provider.allCases.reduce(0) { $0 + (stats[$1]?.stats(.today).cost ?? 0) } }
    var weekSpend: Double { Provider.allCases.reduce(0) { $0 + (stats[$1]?.stats(.week).cost ?? 0) } }
    @Published var onboarded: Bool = UserDefaults.standard.bool(forKey: "onboarded") {
        didSet { UserDefaults.standard.set(onboarded, forKey: "onboarded") }
    }
    /// Opt-in: read Claude Code's Keychain token to fetch 5h / weekly limits.
    @Published var claudeLimitsEnabled: Bool = UserDefaults.standard.bool(forKey: "claudeLimits") {
        didSet {
            UserDefaults.standard.set(claudeLimitsEnabled, forKey: "claudeLimits")
            if claudeLimitsEnabled { refreshClaudeLimits(force: true) } else { limits[.claude] = nil; alerts.update(limits) }
        }
    }
    private var lastClaudeLimitFetch: Date = .distantPast
    @Published var isRefreshing = false
    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var label: String { switch self { case .system: return L("System"); case .light: return L("Light"); case .dark: return L("Dark") } }
        var nsAppearance: NSAppearance? {
            switch self { case .system: return nil; case .light: return NSAppearance(named: .aqua); case .dark: return NSAppearance(named: .darkAqua) }
        }
    }
    @Published var appearance: Appearance = Appearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance"); NSApp.appearance = appearance.nsAppearance }
    }
    /// "system" | "en" | "th"
    @Published var language: String = UserDefaults.standard.string(forKey: "language") ?? "system" {
        didSet { UserDefaults.standard.set(language, forKey: "language"); L10n.current = L10n.resolve(override: language) }
    }
    /// Which provider the menu-bar item represents (nil = all combined).
    @Published var menuBarProvider: Provider? = Provider(rawValue: UserDefaults.standard.string(forKey: "menuBarProvider") ?? "") {
        didSet { UserDefaults.standard.set(menuBarProvider?.rawValue ?? "", forKey: "menuBarProvider") }
    }
    /// Providers worth showing for the current window: has usage in it, or has rate-limit gauges.
    var visibleProviders: [Provider] {
        Provider.allCases.filter { p in
            guard let s = stats[p], s.available else { return false }
            return s.stats(window).total > 0 || !(limits[p]?.limits.isEmpty ?? true)
        }
    }
    /// Tokens shown in the menu bar: selected provider only, or the sum.
    var menuBarTokens: Int {
        if let p = menuBarProvider { return stats[p]?.stats(window).total ?? 0 }
        return totalTokens
    }
    @Published var showNumberInBar: Bool = UserDefaults.standard.object(forKey: "showNumberInBar") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showNumberInBar, forKey: "showNumberInBar") }
    }
    @Published var window: Window = .today {
        didSet { UserDefaults.standard.set(window.rawValue, forKey: "window") }
    }

    private let sources: [UsageSource] = [ClaudeSource(), CodexSource(), GeminiSource(),
                                          ZedSource(), OpenCodeSource(), GeminiSource(provider: .qwen, dir: ".qwen")]
    private let cache = FileCache()
    private var timer: Timer?
    private var bag = Set<AnyCancellable>()

    /// One-time copy of settings from the pre-0.2 bundle id (dev.techit.tokenbar).
    private static func migrateDefaultsIfNeeded() {
        let d = UserDefaults.standard
        guard d.object(forKey: "migrated.v1") == nil else { return }
        if let old = UserDefaults(suiteName: "dev.techit.tokenbar") {
            for (k, v) in old.dictionaryRepresentation() where k.hasPrefix("break.") || k.hasPrefix("limit.")
                || ["window", "appearance", "showNumberInBar", "menuBarProvider"].contains(k) {
                if d.object(forKey: k) == nil { d.set(v, forKey: k) }
            }
        }
        d.set(true, forKey: "migrated.v1")
    }

    /// Existing users (pre-onboarding builds) keep limits on and skip the intro card.
    private static func grandfatherOnboarding() {
        let d = UserDefaults.standard
        guard d.object(forKey: "onboarded") == nil else { return }
        let existing = d.object(forKey: "break.threshold") != nil || d.object(forKey: "window") != nil
        if existing { d.set(true, forKey: "onboarded"); d.set(true, forKey: "claudeLimits") }
    }

    init() {
        Self.migrateDefaultsIfNeeded()
        Self.grandfatherOnboarding()
        L10n.current = L10n.resolve(override: language)
        onboarded = UserDefaults.standard.bool(forKey: "onboarded")
        claudeLimitsEnabled = UserDefaults.standard.bool(forKey: "claudeLimits")
        if let w = UserDefaults.standard.string(forKey: "window"), let win = Window(rawValue: w) {
            window = win
        }
        for p in Provider.allCases { stats[p] = ProviderStats(provider: p) }
        NSApp?.appearance = appearance.nsAppearance
        // Forward nested ObservableObject changes so views observing the store redraw.
        breaks.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        alerts.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        updates.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        budget.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        bindHotkeys()
        refresh()
        updates.autoCheck()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Sum across providers for the current window.
    var totalTokens: Int { Provider.allCases.reduce(0) { $0 + (stats[$1]?.stats(window).total ?? 0) } }
    var totalCost: Double { Provider.allCases.reduce(0) { $0 + (stats[$1]?.stats(window).cost ?? 0) } }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let sources = self.sources
        let cache = self.cache
        Task.detached(priority: .utility) {
            var result: [Provider: ProviderStats] = [:]
            var recent: [Date] = []
            var recent30: [UsageEvent] = []
            let dayAgo = Date().addingTimeInterval(-86400)
            let monthAgo = Calendar.current.date(byAdding: .day, value: -ProviderStats.days, to: Calendar.current.startOfDay(for: Date()))!
            for src in sources {
                var s = ProviderStats(provider: src.provider)
                let files = src.enumerateFiles()
                s.available = src.isAvailable && !files.isEmpty
                var events: [UsageEvent] = []
                for f in files { events += cache.events(for: f) { src.parse(file: $0) } }
                Self.aggregate(events, into: &s)
                recent += events.lazy.map(\.timestamp).filter { $0 > dayAgo }
                recent30 += events.filter { $0.timestamp >= monthAgo }
                result[src.provider] = s
            }
            let final = result
            cache.persist()
            let codexLimits = CodexLimits.read()
            let recentTs = recent
            let recentEv = recent30
            await MainActor.run {
                self.stats = final
                self.recentEvents = recentEv
                self.breaks.update(with: recentTs)
                self.updateFlameTimer()
                self.budget.update(todaySpend: self.todaySpend, weekSpend: self.weekSpend)
                self.limits[.codex] = codexLimits
                self.alerts.update(self.limits)
                self.lastRefresh = Date()
                self.isRefreshing = false
            }
        }
        refreshClaudeLimits()
    }

    /// Claude limits come from the network → throttle to every 5 min (manual refresh forces).
    func refreshClaudeLimits(force: Bool = false) {
        guard claudeLimitsEnabled else { return }
        guard force || Date().timeIntervalSince(lastClaudeLimitFetch) > 300 else { return }
        lastClaudeLimitFetch = Date()
        Task.detached(priority: .utility) {
            let fetched = await ClaudeLimits.fetch()
            await MainActor.run {
                // Keep last good gauges when the fetch fails; surface the error as a stale note.
                var l = fetched
                if l.limits.isEmpty, let prev = self.limits[.claude], !prev.limits.isEmpty {
                    l.limits = prev.limits; l.fetchedAt = prev.fetchedAt; l.plan = l.plan ?? prev.plan
                }
                self.limits[.claude] = l
                self.alerts.update(self.limits)
            }
        }
    }

    nonisolated private static func aggregate(_ events: [UsageEvent], into s: inout ProviderStats) {
        let now = Date()
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        for e in events {
            let cost = Pricing.cost(e)
            for w in Window.allCases where w.contains(e.timestamp, now: now) {
                s.byWindow[w, default: TokenBreakdown()].add(e, cost: cost)
                s.bySource[w, default: [:]][e.source, default: TokenBreakdown()].add(e, cost: cost)
                s.byProject[w, default: [:]][e.project, default: TokenBreakdown()].add(e, cost: cost)
            }
            if Window.month.contains(e.timestamp, now: now) {
                s.byModel[e.model, default: TokenBreakdown()].add(e, cost: cost)
            }
            let dayDiff = cal.dateComponents([.day], from: cal.startOfDay(for: e.timestamp), to: today).day ?? 99
            if dayDiff >= 0 && dayDiff < ProviderStats.days {
                s.dailyTokens[ProviderStats.days - 1 - dayDiff] += e.total
                s.dailyCost[ProviderStats.days - 1 - dayDiff] += cost
            }
            if s.lastActivity == nil || e.timestamp > s.lastActivity! { s.lastActivity = e.timestamp }
        }
    }
}
