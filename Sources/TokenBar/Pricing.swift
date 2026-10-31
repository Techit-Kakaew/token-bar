import Foundation

/// USD per 1M tokens.
///
/// `cacheRead` / `cacheWrite` default to 10 % / 125 % of `input` (Anthropic-style prompt caching) when a row
/// omits them. Rows for vendors that do not bill cache writes set `cacheWrite: 0` explicitly. In
/// `pricing.json` the same applies: omit a key to get the default, write `0` to switch the charge off.
struct ModelPrice: Codable {
    var input: Double
    var output: Double
    var cacheRead: Double
    var cacheWrite: Double

    init(_ input: Double, _ output: Double, cacheRead: Double? = nil, cacheWrite: Double? = nil) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead ?? input * 0.1
        self.cacheWrite = cacheWrite ?? input * 1.25
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(try c.decode(Double.self, forKey: .input),
                  try c.decode(Double.self, forKey: .output),
                  cacheRead: try c.decodeIfPresent(Double.self, forKey: .cacheRead),
                  cacheWrite: try c.decodeIfPresent(Double.self, forKey: .cacheWrite))
    }

    func cost(_ e: UsageEvent) -> Double {
        (Double(e.input) * input
            + Double(e.output) * output
            + Double(e.cacheRead) * cacheRead
            + Double(e.cacheWrite) * cacheWrite) / 1_000_000
    }
}

/// Pricing table. Matched by longest prefix on model id. Override / extend via
/// ~/.config/tokenbar/pricing.json  ({"model-prefix": {"input":..,"output":..,"cacheRead":..,"cacheWrite":..}})
///
/// A model that matches no row is **unpriced**: `cost(_:)` returns nil and the UI shows "—" plus an
/// "N unpriced calls" note instead of a fabricated $0.
enum Pricing {
    static let builtin: [String: ModelPrice] = [
        // Anthropic (first-party API rates, 2026-06). Cache write = 1.25× input (5-min TTL).
        "claude-fable-5-1": ModelPrice(10, 50, cacheRead: 0.25),
        "claude-fable-5": ModelPrice(10, 50, cacheRead: 1.0),
        "claude-mythos": ModelPrice(10, 50, cacheRead: 0.25),
        "claude-opus-5": ModelPrice(5, 25),
        "claude-opus-4-8": ModelPrice(5, 25),
        "claude-opus-4-7": ModelPrice(5, 25),
        "claude-opus-4-6": ModelPrice(5, 25),
        "claude-opus-4-5": ModelPrice(5, 25),
        "claude-opus-4": ModelPrice(15, 75),
        "claude-sonnet-5": ModelPrice(2, 10),
        "claude-sonnet-4-6": ModelPrice(3, 15),
        "claude-sonnet-4": ModelPrice(3, 15),
        "claude-haiku-4-5": ModelPrice(1, 5),
        "claude-haiku": ModelPrice(0.8, 4),
        // OpenAI — standard tier, ≤272K context, developers.openai.com/api/docs/pricing (2026-10-31).
        // Cached input is billed at a discount; there is no cache-write charge.
        "gpt-6-astra": ModelPrice(10, 50, cacheRead: 1.0, cacheWrite: 0),
        "gpt-6.1-sol": ModelPrice(2, 10, cacheRead: 0.1, cacheWrite: 0),
        "gpt-6.1-terra": ModelPrice(1, 5, cacheRead: 0.05, cacheWrite: 0),
        "gpt-6-sol": ModelPrice(2, 10, cacheRead: 0.2, cacheWrite: 0),
        "gpt-6-luna": ModelPrice(0.1, 0.5, cacheRead: 0.01, cacheWrite: 0),
        "gpt-5.6-sol": ModelPrice(4, 20, cacheRead: 0.4, cacheWrite: 0),       // promo through 2026-11-21
        "gpt-5.6-terra": ModelPrice(2, 12, cacheRead: 0.2, cacheWrite: 0),
        "gpt-5.6-luna": ModelPrice(0.2, 1.2, cacheRead: 0.02, cacheWrite: 0),
        "gpt-5.5-pro": ModelPrice(30, 180, cacheRead: 30, cacheWrite: 0),
        "gpt-5.5": ModelPrice(5, 30, cacheRead: 0.5, cacheWrite: 0),
        "gpt-5.4-pro": ModelPrice(30, 180, cacheRead: 30, cacheWrite: 0),
        "gpt-5.4-mini": ModelPrice(0.75, 4.5, cacheRead: 0.075, cacheWrite: 0),
        "gpt-5.4-nano": ModelPrice(0.2, 1.25, cacheRead: 0.02, cacheWrite: 0),
        "gpt-5.4": ModelPrice(2.5, 15, cacheRead: 0.25, cacheWrite: 0),
        "gpt-5.3-codex": ModelPrice(1.75, 14, cacheRead: 0.175, cacheWrite: 0),
        "gpt-5.2-pro": ModelPrice(21, 168, cacheRead: 21, cacheWrite: 0),
        "gpt-5.2": ModelPrice(1.75, 14, cacheRead: 0.175, cacheWrite: 0),
        "gpt-5.1": ModelPrice(1.25, 10, cacheRead: 0.125, cacheWrite: 0),
        "gpt-5-codex": ModelPrice(1.25, 10, cacheRead: 0.125, cacheWrite: 0),  // not on the page; assumed = gpt-5
        "gpt-5-mini": ModelPrice(0.25, 2, cacheRead: 0.025, cacheWrite: 0),
        "gpt-5-nano": ModelPrice(0.05, 0.4, cacheRead: 0.005, cacheWrite: 0),
        "gpt-5-pro": ModelPrice(15, 120, cacheRead: 15, cacheWrite: 0),
        "gpt-5": ModelPrice(1.25, 10, cacheRead: 0.125, cacheWrite: 0),
        "gpt-4.1-mini": ModelPrice(0.4, 1.6, cacheRead: 0.1, cacheWrite: 0),
        "gpt-4.1": ModelPrice(2, 8, cacheRead: 0.5, cacheWrite: 0),
        "gpt-4o-mini": ModelPrice(0.15, 0.6, cacheRead: 0.075, cacheWrite: 0),
        "gpt-4o": ModelPrice(2.5, 10, cacheRead: 1.25, cacheWrite: 0),
        "o4-mini": ModelPrice(1.1, 4.4, cacheRead: 0.275, cacheWrite: 0),
        "o3-mini": ModelPrice(1.1, 4.4, cacheRead: 0.55, cacheWrite: 0),
        "o3": ModelPrice(2, 8, cacheRead: 0.5, cacheWrite: 0),
        "codex": ModelPrice(1.25, 10, cacheRead: 0.125, cacheWrite: 0),        // codex-auto-review etc.; assumed = gpt-5
        // Google (approximate; no cache-write charge, explicit caching bills storage per hour instead)
        "gemini-3-pro": ModelPrice(2, 12, cacheWrite: 0),
        "gemini-3-flash": ModelPrice(0.5, 3, cacheWrite: 0),
        "gemini-2.5-pro": ModelPrice(1.25, 10, cacheWrite: 0),
        "gemini-2.5-flash": ModelPrice(0.3, 2.5, cacheWrite: 0),
        "gemini": ModelPrice(1.25, 10, cacheWrite: 0),
        // Alibaba (approximate; no cache-write charge)
        "qwen3-coder-plus": ModelPrice(1, 5, cacheWrite: 0),
        "qwen3-coder": ModelPrice(0.3, 1.2, cacheWrite: 0),
        "qwen": ModelPrice(0.5, 2, cacheWrite: 0),
    ]

    static var table: [String: ModelPrice] = {
        var t = builtin
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/tokenbar/pricing.json")
        if let data = try? Data(contentsOf: url),
           let extra = try? JSONDecoder().decode([String: ModelPrice].self, from: data) {
            t.merge(extra) { _, new in new }
        }
        return t
    }()

    private static var cache: [String: ModelPrice?] = [:]

    static func price(for model: String) -> ModelPrice? {
        if let c = cache[model] { return c }
        let m = model.lowercased()
        // longest matching prefix wins
        let hit = table.keys
            .filter { m.hasPrefix($0) || m.contains($0) }
            .max { $0.count < $1.count }
            .flatMap { table[$0] }
        cache[model] = hit
        return hit
    }

    /// nil when the model is not in the table (unpriced) — never a fabricated 0.
    static func cost(_ e: UsageEvent) -> Double? {
        price(for: e.model)?.cost(e)
    }
}
