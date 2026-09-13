import Foundation

/// Zed's native agent panel: ~/Library/Application Support/Zed/threads/threads.db (SQLite).
/// Each row's `data` is zstd-compressed JSON with `request_token_usage` (per message: input/output tokens)
/// and `model: {provider, model}`. Messages carry no timestamps → all usage is attributed to `updated_at`.
/// Needs the `zstd` CLI (Homebrew) to decompress; without it the provider stays hidden.
struct ZedSource: UsageSource {
    let provider = Provider.zed
    var roots: [URL] {
        [FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Zed/threads")]
    }

    func matches(_ url: URL) -> Bool { url.lastPathComponent == "threads.db" && zstdPath != nil }

    private var zstdPath: String? {
        ["/opt/homebrew/bin/zstd", "/usr/local/bin/zstd", "/usr/bin/zstd"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func run(_ exe: String, _ args: [String], stdin: Data? = nil) -> Data? {
        let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        let inPipe = stdin.map { _ in Pipe() }; p.standardInput = inPipe
        do { try p.run() } catch { return nil }
        if let stdin, let inPipe { inPipe.fileHandleForWriting.write(stdin); inPipe.fileHandleForWriting.closeFile() }
        let d = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return p.terminationStatus == 0 ? d : nil
    }

    func parse(file: URL) -> [UsageEvent] {
        guard let zstd = zstdPath,
              let dump = run("/usr/bin/sqlite3", ["-readonly", "-separator", "\t", file.path,
                                                 "select id, updated_at, data_type, hex(data) from threads"]),
              let text = String(data: dump, encoding: .utf8) else { return [] }
        var events: [UsageEvent] = []
        for line in text.split(separator: "\n") {
            let cols = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
            guard cols.count == 4, let ts = parseDate(String(cols[1])) else { continue }
            guard let raw = Data(hex: String(cols[3])) else { continue }
            let json: Data? = cols[2] == "zstd" ? run(zstd, ["-dc"], stdin: raw) : raw
            guard let json, let t = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { continue }
            let modelInfo = t["model"] as? [String: Any]
            let model = modelInfo?["model"] as? String ?? "unknown"
            let vendor = modelInfo?["provider"] as? String ?? "zed"
            // request_token_usage: {messageId: {input_tokens, output_tokens}} (0.3) or [{...}] (0.2)
            var usages: [[String: Any]] = []
            if let d = t["request_token_usage"] as? [String: Any] { usages = d.values.compactMap { $0 as? [String: Any] } }
            else if let a = t["request_token_usage"] as? [[String: Any]] { usages = a }
            for u in usages {
                let i = int(u["input_tokens"]), o = int(u["output_tokens"])
                if i + o == 0 { continue }
                events.append(UsageEvent(provider: .zed, timestamp: ts, model: model, input: i, output: o,
                                         cacheRead: int(u["cache_read_input_tokens"]),
                                         cacheWrite: int(u["cache_creation_input_tokens"]),
                                         source: "Zed · \(vendor)", project: t["title"] as? String ?? "—"))
            }
        }
        return events
    }
}

private extension Data {
    init?(hex: String) {
        let chars = Array(hex.utf8); guard chars.count % 2 == 0 else { return nil }
        var out = Data(capacity: chars.count / 2)
        func v(_ c: UInt8) -> UInt8? {
            switch c { case 48...57: return c - 48; case 65...70: return c - 55; case 97...102: return c - 87; default: return nil }
        }
        var i = 0
        while i < chars.count { guard let h = v(chars[i]), let l = v(chars[i + 1]) else { return nil }; out.append(h << 4 | l); i += 2 }
        self = out
    }
}
