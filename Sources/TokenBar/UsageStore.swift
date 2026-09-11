import Foundation
import Combine

@MainActor
final class UsageStore: ObservableObject {
    @Published var stats: [Provider: ProviderStats] = [:]
    @Published var lastRefresh: Date?
    @Published var limits: [Provider: ProviderLimits] = [:]
    let breaks = BreakReminder()
    let alerts = LimitAlerts()
    private var lastClaudeLimitFetch: Date = .distantPast
    @Published var isRefreshing = false
    @Published var showNumberInBar: Bool = UserDefaults.standard.object(forKey: "showNumberInBar") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showNumberInBar, forKey: "showNumberInBar") }
    }
    @Published var window: Window = .today {
        didSet { UserDefaults.standard.set(window.rawValue, forKey: "window") }
    }

    private let sources: [UsageSource] = [ClaudeSource(), CodexSource(), GeminiSource()]
    private let cache = FileCache()
    private var timer: Timer?
    private var bag = Set<AnyCancellable>()

    init() {
        if let w = UserDefaults.standard.string(forKey: "window"), let win = Window(rawValue: w) {
            window = win
        }
        for p in Provider.allCases { stats[p] = ProviderStats(provider: p) }
        // Forward nested ObservableObject changes so views observing the store redraw.
        breaks.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        alerts.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        refresh()
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
            let dayAgo = Date().addingTimeInterval(-86400)
            for src in sources {
                var s = ProviderStats(provider: src.provider)
                let files = src.enumerateFiles()
                s.available = src.isAvailable && !files.isEmpty
                var events: [UsageEvent] = []
                for f in files { events += cache.events(for: f) { src.parse(file: $0) } }
                Self.aggregate(events, into: &s)
                recent += events.lazy.map(\.timestamp).filter { $0 > dayAgo }
                result[src.provider] = s
            }
            let final = result
            let codexLimits = CodexLimits.read()
            let recentTs = recent
            await MainActor.run {
                self.stats = final
                self.breaks.update(with: recentTs)
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
