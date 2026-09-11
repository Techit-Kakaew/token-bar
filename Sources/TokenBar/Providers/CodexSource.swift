import Foundation

/// ~/.codex/sessions/**/*.jsonl — `event_msg` / `token_count` events with `info.last_token_usage`.
/// Model comes from the most recent `turn_context.payload.model` line.
struct CodexSource: UsageSource {
    let provider = Provider.codex
    var roots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let base = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".codex")
        return [base.appendingPathComponent("sessions"), base.appendingPathComponent("archived_sessions")]
    }

    func matches(_ url: URL) -> Bool { url.pathExtension == "jsonl" }

    func parse(file: URL) -> [UsageEvent] {
        var events: [UsageEvent] = []
        var model = "unknown"
        var source = "Codex CLI"
        var project = "—"
        // Both turn_context and token_count lines contain "model" or "token_count"; scan lines with either.
        forEachLine(of: file, containing: "\"type\":\"") { obj in
            guard let type = obj["type"] as? String,
                  let payload = obj["payload"] as? [String: Any] else { return }
            if type == "turn_context" {
                if let m = payload["model"] as? String { model = m }
                if let c = payload["cwd"] as? String { project = projectName(c) }
                return
            }
            if type == "session_meta" {
                if let m = payload["model"] as? String { model = m }
                if let c = payload["cwd"] as? String { project = projectName(c) }
                let originator = (payload["originator"] as? String ?? "").lowercased()
                let src = (payload["source"] as? String ?? "").lowercased()
                if src == "vscode" || originator.contains("vscode") { source = "VS Code" }
                else if originator.contains("desktop") { source = "Codex Desktop" }
                else if originator.contains("tui") || originator.contains("cli") || src == "cli" { source = "Codex CLI" }
                else if !originator.isEmpty { source = payload["originator"] as? String ?? source }
                return
            }
            guard type == "event_msg",
                  (payload["type"] as? String) == "token_count",
                  let info = payload["info"] as? [String: Any],
                  let last = info["last_token_usage"] as? [String: Any],
                  let ts = parseDate(obj["timestamp"] as? String) else { return }
            let input = int(last["input_tokens"])
            let cached = int(last["cached_input_tokens"])
            let out = int(last["output_tokens"])
            if input + out == 0 { return }
            // Codex `input_tokens` includes cached tokens → split them out.
            events.append(UsageEvent(
                provider: .codex, timestamp: ts, model: model,
                input: max(0, input - cached), output: out,
                cacheRead: cached, cacheWrite: int(last["cache_write_input_tokens"]),
                source: source, project: project))
        }
        return events
    }
}
