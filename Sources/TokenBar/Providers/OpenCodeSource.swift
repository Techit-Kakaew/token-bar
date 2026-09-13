import Foundation

/// OpenCode (opencode.ai) JSON storage:
///   ~/.local/share/opencode/storage/message/<sessionID>/<messageID>.json
/// Assistant messages carry `tokens: {input, output, reasoning, cache: {read, write}}`, `modelID`,
/// `providerID`, `time: {created, completed}` (ms since epoch). Written without sample data → tolerant parsing.
struct OpenCodeSource: UsageSource {
    let provider = Provider.opencode
    var roots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let xdg = ProcessInfo.processInfo.environment["XDG_DATA_HOME"].map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".local/share")
        return [xdg.appendingPathComponent("opencode/storage/message")]
    }

    func matches(_ url: URL) -> Bool { url.pathExtension == "json" }

    func parse(file: URL) -> [UsageEvent] {
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe),
              let m = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (m["role"] as? String) == "assistant",
              let tokens = m["tokens"] as? [String: Any] else { return [] }
        let time = m["time"] as? [String: Any]
        let ms = (time?["completed"] as? NSNumber) ?? (time?["created"] as? NSNumber)
        guard let ms else { return [] }
        let ts = Date(timeIntervalSince1970: ms.doubleValue / 1000)
        let cache = tokens["cache"] as? [String: Any] ?? [:]
        let model = m["modelID"] as? String ?? "unknown"
        let input = int(tokens["input"]), output = int(tokens["output"]) + int(tokens["reasoning"])
        if input + output == 0 { return [] }
        // sessionID folder is the parent dir; project is not stored on the message → use provider id as source
        let providerID = m["providerID"] as? String ?? "opencode"
        return [UsageEvent(provider: .opencode, timestamp: ts, model: model,
                           input: input, output: output,
                           cacheRead: int(cache["read"]), cacheWrite: int(cache["write"]),
                           source: "OpenCode · \(providerID)")]
    }
}
