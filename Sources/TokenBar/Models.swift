import Foundation

enum Provider: String, CaseIterable, Identifiable, Codable {
    case claude, codex, gemini, zed, opencode, qwen
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex CLI"
        case .gemini: return "Gemini CLI"
        case .zed: return "Zed Agent"
        case .opencode: return "OpenCode"
        case .qwen: return "Qwen Code"
        }
    }

    var vendor: String {
        switch self {
        case .claude: return "Anthropic"
        case .codex: return "OpenAI"
        case .gemini: return "Google"
        case .zed: return "Zed Industries · multi-model"
        case .opencode: return "SST · multi-model"
        case .qwen: return "Alibaba"
        }
    }

    /// SVG logo file name in Resources/logos (nil → SF Symbol fallback).
    var logoFile: String {
        switch self {
        case .claude: return "claude"
        case .codex: return "openai"
        case .gemini: return "gemini"
        case .zed: return "zed"
        case .opencode: return "opencode"
        case .qwen: return "qwen"
        }
    }

    var symbol: String {
        switch self {
        case .claude: return "sparkle"
        case .codex: return "terminal"
        case .gemini: return "diamond"
        case .zed: return "bolt.fill"
        case .opencode: return "chevron.left.forwardslash.chevron.right"
        case .qwen: return "cloud.fill"
        }
    }

    /// RGB accent colour (0-1)
    var accent: (Double, Double, Double) {
        switch self {
        case .claude: return (0.85, 0.47, 0.34)   // terracotta
        case .codex: return (0.30, 0.85, 0.65)    // mint
        case .gemini: return (0.45, 0.60, 1.00)   // periwinkle
        case .zed: return (0.55, 0.50, 1.00)      // violet
        case .opencode: return (1.00, 0.80, 0.35) // amber
        case .qwen: return (0.60, 0.40, 0.95)     // purple
        }
    }
}

/// One API call worth of usage.
struct UsageEvent: Codable {
    let provider: Provider
    let timestamp: Date
    let model: String
    let input: Int
    let output: Int
    let cacheRead: Int
    let cacheWrite: Int
    /// Where the call came from: "CLI", "Desktop", "Zed / SDK", "VS Code" …
    var source: String = "Unknown"
    /// Project folder name (last path component of cwd), if known.
    var project: String = "—"
    /// Conversation / session id (file name or embedded id).
    var sessionId: String = ""
    /// Tokens sent as context in this call (prompt incl. cache); 0 if unknown.
    var contextTokens: Int = 0
    /// Model context window reported by the tool (Codex), else 0 → look up by model.
    var contextWindow: Int = 0
    /// Session title = the user's first prompt (trimmed), if known.
    var title: String = ""
    /// True when this call was made by a subagent inside the session (Claude `agentId`).
    var isSubagent: Bool = false

    var total: Int { input + output + cacheRead + cacheWrite }
}

/// Token totals for events older than the detail horizon, keyed by (model, source, project).
/// Cost is NOT stored: it is linear in tokens per model, so recomputing from these totals at
/// aggregation time gives the same result as summing per-event costs (and honours pricing changes).
struct ArchiveBucket: Codable, Hashable {
    let model: String
    let source: String
    let project: String
    var input = 0, output = 0, cacheRead = 0, cacheWrite = 0, calls = 0
    var last: Date = .distantPast

    var total: Int { input + output + cacheRead + cacheWrite }
    var asEvent: UsageEvent {   // synthetic event carrying the bucket's totals, for Pricing.cost
        UsageEvent(provider: .claude, timestamp: last, model: model, input: input, output: output,
                   cacheRead: cacheRead, cacheWrite: cacheWrite, source: source, project: project)
    }

    mutating func add(_ e: UsageEvent) {
        input += e.input; output += e.output; cacheRead += e.cacheRead; cacheWrite += e.cacheWrite; calls += 1
        if e.timestamp > last { last = e.timestamp }
    }
}

/// Parsed contents of one log file: full events inside the detail horizon, totals beyond it.
struct FileEvents: Codable {
    var recent: [UsageEvent] = []
    var archive: [ArchiveBucket] = []

    /// Events at or after `horizon` stay as-is; older ones fold into archive buckets.
    static func split(_ events: [UsageEvent], horizon: Date) -> FileEvents {
        var out = FileEvents()
        var buckets: [String: ArchiveBucket] = [:]
        for e in events {
            if e.timestamp >= horizon { out.recent.append(e); continue }
            let k = "\(e.model)|\(e.source)|\(e.project)"
            var b = buckets[k] ?? ArchiveBucket(model: e.model, source: e.source, project: e.project)
            b.add(e); buckets[k] = b
        }
        out.archive = Array(buckets.values)
        return out
    }

    /// Re-fold events that have aged past a newer horizon (called on cache load).
    mutating func refold(horizon: Date) -> Bool {
        guard recent.contains(where: { $0.timestamp < horizon }) else { return false }
        let again = Self.split(recent, horizon: horizon)
        var buckets = Dictionary(uniqueKeysWithValues: archive.map { ("\($0.model)|\($0.source)|\($0.project)", $0) })
        for b in again.archive {
            let k = "\(b.model)|\(b.source)|\(b.project)"
            if var cur = buckets[k] {
                cur.input += b.input; cur.output += b.output; cur.cacheRead += b.cacheRead; cur.cacheWrite += b.cacheWrite
                cur.calls += b.calls; cur.last = max(cur.last, b.last); buckets[k] = cur
            } else { buckets[k] = b }
        }
        recent = again.recent; archive = Array(buckets.values)
        return true
    }
}

/// Context-window sizes (tokens) by model-id prefix; longest prefix wins. Override via pricing.json "contextWindow".
enum ContextWindows {
    static let table: [String: Int] = [
        "claude-opus-5": 1_000_000, "claude-fable": 1_000_000, "claude-mythos": 1_000_000,
        "claude-opus-4-8": 1_000_000, "claude-opus-4-7": 1_000_000, "claude-opus-4-6": 1_000_000,
        "claude-sonnet-5": 1_000_000, "claude-sonnet-4-6": 1_000_000, "claude-sonnet-4": 200_000,
        "claude-opus-4": 200_000, "claude-haiku": 200_000,
        "gpt-6": 400_000, "gpt-5": 400_000, "codex": 400_000,
        "gemini": 1_000_000, "qwen": 256_000,
    ]
    static func window(for model: String) -> Int {
        let m = model.lowercased()
        return table.keys.filter { m.hasPrefix($0) }.max { $0.count < $1.count }.flatMap { table[$0] } ?? 200_000
    }
}

/// A conversation that has had activity recently.
struct LiveSession: Identifiable {
    enum State { case active, idle }
    let id: String
    let provider: Provider
    let project: String
    let source: String
    let model: String
    let started: Date
    let last: Date
    let calls: Int
    let cost: Double
    let tokens: Int
    let contextTokens: Int
    let contextWindow: Int
    let title: String
    let subagentCalls: Int
    var contextRatio: Double { contextWindow > 0 ? Double(contextTokens) / Double(contextWindow) : 0 }
    var state: State { Date().timeIntervalSince(last) < 180 ? .active : .idle }
    /// Last 4 chars of the session id — disambiguates same-project sessions without a title.
    var shortId: String { String(id.split(separator: "|").last?.suffix(4) ?? "") }
    /// Sort key: near-full context first, then active, then most recent.
    var priority: (Int, Int, Double) { (contextRatio >= 0.8 ? 0 : 1, state == .active ? 0 : 1, -last.timeIntervalSinceReferenceDate) }
}

/// Sessions of one provider+project, for the grouped popover list.
struct LiveGroup: Identifiable {
    let id: String
    let provider: Provider
    let project: String
    let sessions: [LiveSession]
    var activeCount: Int { sessions.filter { $0.state == .active }.count }
    var maxContext: Double { sessions.map(\.contextRatio).max() ?? 0 }
    var cost: Double { sessions.reduce(0) { $0 + $1.cost } }
    var last: Date { sessions.map(\.last).max() ?? .distantPast }
    var priority: (Int, Int, Double) { (maxContext >= 0.8 ? 0 : 1, activeCount > 0 ? 0 : 1, -last.timeIntervalSinceReferenceDate) }
}

/// Strip command/tool noise and squash whitespace for a one-line session title.
func sessionTitle(from raw: String, limit: Int = 60) -> String {
    var t = raw.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    if t.hasPrefix("<") { return "" }                // <command-name>, <local-command-stdout>, tool_result…
    while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
    if t.count > limit { t = String(t.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…" }
    return t
}

struct TokenBreakdown {
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheWrite = 0
    var cost: Double = 0
    var calls = 0

    var total: Int { input + output + cacheRead + cacheWrite }

    mutating func add(_ e: UsageEvent, cost c: Double) {
        input += e.input
        output += e.output
        cacheRead += e.cacheRead
        cacheWrite += e.cacheWrite
        cost += c
        calls += 1
    }

    mutating func merge(_ o: TokenBreakdown) {
        input += o.input; output += o.output; cacheRead += o.cacheRead; cacheWrite += o.cacheWrite; cost += o.cost; calls += o.calls
    }
}

enum Window: String, CaseIterable, Identifiable {
    case today = "Today", week = "7d", month = "30d", all = "All"
    var id: String { rawValue }
    var label: String { L(rawValue) }

    func contains(_ d: Date, now: Date = Date()) -> Bool {
        let cal = Calendar.current
        switch self {
        case .today: return cal.isDateInToday(d)
        case .week: return d >= cal.date(byAdding: .day, value: -7, to: now)!
        case .month: return d >= cal.date(byAdding: .day, value: -30, to: now)!
        case .all: return true
        }
    }
}

struct ProviderStats {
    let provider: Provider
    var byWindow: [Window: TokenBreakdown] = [:]
    var byModel: [String: TokenBreakdown] = [:]      // last 30d
    var bySource: [Window: [String: TokenBreakdown]] = [:]
    var byProject: [Window: [String: TokenBreakdown]] = [:]
    static let days = 30
    var dailyTokens: [Int] = Array(repeating: 0, count: days)      // oldest first
    var dailyCost: [Double] = Array(repeating: 0, count: days)
    /// Last 14 days for the popover sparkline.
    var daily: [Int] { Array(dailyTokens.suffix(14)) }
    var lastActivity: Date?
    var available = false

    func stats(_ w: Window) -> TokenBreakdown { byWindow[w] ?? TokenBreakdown() }
    func sources(_ w: Window) -> [(name: String, stats: TokenBreakdown)] {
        (bySource[w] ?? [:]).map { ($0.key, $0.value) }.sorted { $0.1.total > $1.1.total }
    }
    func projects(_ w: Window) -> [(name: String, stats: TokenBreakdown)] {
        (byProject[w] ?? [:]).map { ($0.key, $0.value) }.sorted { $0.1.total > $1.1.total }
    }
}

// MARK: - Formatting

extension Int {
    var compact: String {
        let v = Double(self)
        switch v {
        case 1_000_000_000...: return String(format: "%.2fB", v / 1_000_000_000)
        case 1_000_000...: return String(format: "%.1fM", v / 1_000_000)
        case 1_000...: return String(format: "%.1fK", v / 1_000)
        default: return "\(self)"
        }
    }
}

extension Double {
    var usd: String {
        if self == 0 { return "$0" }
        if self >= 100 { return String(format: "$%.0f", self) }
        if self >= 1 { return String(format: "$%.2f", self) }
        return String(format: "$%.3f", self)
    }
}

extension Date {
    /// "12s", "25m", "3h", "2d" — for tight columns.
    var agoTiny: String {
        let s = Int(-timeIntervalSinceNow)
        switch s {
        case ..<60: return "\(max(s, 0))s"
        case ..<3600: return "\(s / 60)m"
        case ..<86400: return "\(s / 3600)h"
        default: return "\(s / 86400)d"
        }
    }
    /// "12s ago", "25m ago", "3h ago", "2d ago"
    var agoShort: String {
        let s = Int(-timeIntervalSinceNow)
        switch s {
        case ..<60: return L("%ds ago", max(s, 0))
        case ..<3600: return L("%dm ago", s / 60)
        case ..<86400: return L("%dh ago", s / 3600)
        default: return L("%dd ago", s / 86400)
        }
    }
}
