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

    var total: Int { input + output + cacheRead + cacheWrite }
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
