import Foundation

/// USD per 1M tokens.
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

    func cost(_ e: UsageEvent) -> Double {
        (Double(e.input) * input
            + Double(e.output) * output
            + Double(e.cacheRead) * cacheRead
            + Double(e.cacheWrite) * cacheWrite) / 1_000_000
    }
}

/// Pricing table. Matched by longest prefix on model id. Override / extend via
/// ~/.config/tokenbar/pricing.json  ({"model-prefix": {"input":..,"output":..,"cacheRead":..,"cacheWrite":..}})
enum Pricing {
    static let builtin: [String: ModelPrice] = [
        // Anthropic (first-party API rates, 2026-06)
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
        // OpenAI (approximate list prices; edit pricing.json to correct)
        "gpt-6": ModelPrice(2.5, 20),
        "gpt-5.6": ModelPrice(1.75, 14),
        "gpt-5.5": ModelPrice(1.75, 14),
        "gpt-5.4-mini": ModelPrice(0.4, 1.6),
        "gpt-5.4": ModelPrice(1.25, 10),
        "gpt-5-codex": ModelPrice(1.25, 10),
        "gpt-5-mini": ModelPrice(0.25, 2),
        "gpt-5": ModelPrice(1.25, 10),
        "codex": ModelPrice(1.25, 10),
        "o3": ModelPrice(2, 8),
        // Google
        "gemini-3-pro": ModelPrice(2, 12),
        "gemini-3-flash": ModelPrice(0.5, 3),
        "gemini-2.5-pro": ModelPrice(1.25, 10),
        "gemini-2.5-flash": ModelPrice(0.3, 2.5),
        "gemini": ModelPrice(1.25, 10),
        // Alibaba (approximate)
        "qwen3-coder-plus": ModelPrice(1, 5),
        "qwen3-coder": ModelPrice(0.3, 1.2),
        "qwen": ModelPrice(0.5, 2),
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

    static func cost(_ e: UsageEvent) -> Double {
        price(for: e.model)?.cost(e) ?? 0
    }
}
