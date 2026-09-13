import Foundation

/// ~/.gemini/tmp/<hash>/chats/*.json — JSON array (or {messages:[...]}) of messages;
/// `gemini` messages carry `tokens: {input, output, cached, thoughts, tool, total}` and `model`.
struct GeminiSource: UsageSource {
    var provider = Provider.gemini
    /// Config dir under $HOME (".gemini" or ".qwen" — Qwen Code is a Gemini CLI fork with the same layout).
    var dir = ".gemini"
    var roots: [URL] {
        [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("\(dir)/tmp")]
    }

    func matches(_ url: URL) -> Bool {
        url.pathExtension == "json" && url.deletingLastPathComponent().lastPathComponent == "chats"
    }

    func parse(file: URL) -> [UsageEvent] {
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe),
              let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let messages: [[String: Any]]
        if let arr = root as? [[String: Any]] { messages = arr }
        else if let dict = root as? [String: Any], let arr = dict["messages"] as? [[String: Any]] { messages = arr }
        else { return [] }

        var events: [UsageEvent] = []
        for m in messages {
            guard let tokens = m["tokens"] as? [String: Any],
                  let ts = parseDate(m["timestamp"] as? String) else { continue }
            let type = m["type"] as? String ?? ""
            if type == "user" { continue }
            let model = m["model"] as? String ?? (provider == .qwen ? "qwen" : "gemini")
            events.append(UsageEvent(
                provider: provider, timestamp: ts, model: model,
                input: int(tokens["input"]),
                output: int(tokens["output"]) + int(tokens["thoughts"]) + int(tokens["tool"]),
                cacheRead: int(tokens["cached"]), cacheWrite: 0, source: provider.displayName))
        }
        return events
    }
}
