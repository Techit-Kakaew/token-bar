import Foundation

/// ~/.claude/projects/**/*.jsonl — one JSON object per line; assistant messages carry `message.usage`.
struct ClaudeSource: UsageSource {
    let provider = Provider.claude
    var roots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var r = [home.appendingPathComponent(".claude/projects")]
        if let cfg = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
            r.append(URL(fileURLWithPath: cfg).appendingPathComponent("projects"))
        }
        return r
    }

    func matches(_ url: URL) -> Bool { url.pathExtension == "jsonl" }

    /// Claude Code `entrypoint` → human label.
    static func sourceName(_ ep: String?) -> String {
        switch ep {
        case "cli": return "Terminal (CLI)"
        case "claude-desktop": return "Claude Desktop"
        case "sdk-ts", "sdk-py", "sdk-cli": return "Zed / Agent SDK"
        case "claude-vscode", "vscode": return "VS Code"
        case "jetbrains": return "JetBrains"
        case let e?: return e
        case nil: return "Unknown"
        }
    }

    func parse(file: URL) -> [UsageEvent] {
        var events: [UsageEvent] = []
        var seen = Set<String>()
        forEachLine(of: file, containing: "\"usage\"") { obj in
            guard (obj["type"] as? String) == "assistant",
                  let msg = obj["message"] as? [String: Any],
                  let usage = msg["usage"] as? [String: Any],
                  let ts = parseDate(obj["timestamp"] as? String) else { return }
            // Claude Code writes one line per content block with identical usage → dedupe.
            let msgId = msg["id"] as? String ?? ""
            let reqId = obj["requestId"] as? String ?? ""
            let key = msgId + ":" + reqId
            if !msgId.isEmpty, !seen.insert(key).inserted { return }
            let model = msg["model"] as? String ?? "unknown"
            if model == "<synthetic>" { return }
            let input = int(usage["input_tokens"]), cr = int(usage["cache_read_input_tokens"]), cw = int(usage["cache_creation_input_tokens"])
            events.append(UsageEvent(
                provider: .claude, timestamp: ts, model: model,
                input: input, output: int(usage["output_tokens"]), cacheRead: cr, cacheWrite: cw,
                source: Self.sourceName(obj["entrypoint"] as? String),
                project: projectName(obj["cwd"] as? String),
                sessionId: obj["sessionId"] as? String ?? file.deletingPathExtension().lastPathComponent,
                contextTokens: input + cr + cw))
        }
        return events
    }
}
