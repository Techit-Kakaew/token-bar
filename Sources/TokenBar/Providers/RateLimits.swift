import Foundation

/// One rate-limit window (e.g. 5-hour session, weekly).
struct RateLimit: Identifiable {
    let name: String        // "5h", "Weekly", "Weekly · Fable"
    let percent: Double     // 0-100 used
    let resetsAt: Date?
    var id: String { name }

    /// "2h 36m · 15:00" (same day), "9h 10m · tmr 02:00", or "Thu 02:00" for far-off resets.
    var resetText: String {
        guard let r = resetsAt else { return "" }
        let s = r.timeIntervalSinceNow
        if s <= 0 { return "resetting" }
        let cal = Calendar.current
        let clock = DateFormatter(); clock.dateFormat = "HH:mm"
        if s >= 48 * 3600 {
            let f = DateFormatter(); f.dateFormat = "EEE HH:mm"
            return f.string(from: r)
        }
        let h = Int(s) / 3600, m = (Int(s) % 3600) / 60
        let countdown = h > 0 ? "\(h)h \(m)m" : "\(m)m"
        let day = cal.isDateInToday(r) ? "" : (cal.isDateInTomorrow(r) ? "tmr " : "")
        return "\(countdown) · \(day)\(clock.string(from: r))"
    }
}

struct ProviderLimits {
    var limits: [RateLimit] = []
    var plan: String?
    var error: String?
    var fetchedAt: Date?
}

// MARK: - Codex: last `rate_limits` payload in the newest session file.

enum CodexLimits {
    static func read() -> ProviderLimits {
        let src = CodexSource()
        let fm = FileManager.default
        // newest file by mtime
        let files = src.enumerateFiles()
            .compactMap { u -> (URL, Date)? in
                let m = (try? fm.attributesOfItem(atPath: u.path))?[.modificationDate] as? Date
                return m.map { (u, $0) }
            }
            .sorted { $0.1 > $1.1 }
        var out = ProviderLimits()
        for (file, _) in files.prefix(5) {
            var found: [String: Any]?
            var ts: Date?
            forEachLine(of: file, containing: "\"rate_limits\"") { obj in
                guard let p = obj["payload"] as? [String: Any],
                      let rl = p["rate_limits"] as? [String: Any] else { return }
                found = rl; ts = parseDate(obj["timestamp"] as? String)
            }
            guard let rl = found else { continue }
            out.plan = rl["plan_type"] as? String
            out.fetchedAt = ts
            for key in ["primary", "secondary"] {
                guard let w = rl[key] as? [String: Any] else { continue }
                let mins = int(w["window_minutes"])
                let name: String
                switch mins {
                case 0..<120: name = "\(mins)m"
                case 120..<1440: name = "\(mins / 60)h"
                case 10080: name = "Weekly"
                default: name = "\(mins / 1440)d"
                }
                let reset = (w["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
                out.limits.append(RateLimit(name: name, percent: (w["used_percent"] as? NSNumber)?.doubleValue ?? 0, resetsAt: reset))
            }
            break
        }
        if out.limits.isEmpty { out.error = "no rate-limit data in logs" }
        return out
    }
}

// MARK: - Claude: OAuth usage endpoint using Claude Code's Keychain credentials.

enum ClaudeLimits {
    struct Creds { let token: String; let expiresAt: Date?; let subscription: String? }
    struct Err: Error { let msg: String; init(_ m: String) { msg = m } }

    /// Reads the "Claude Code-credentials" keychain item via `security`.
    /// First call triggers a Keychain prompt → choose "Always Allow".
    static func credentials() -> Result<Creds, Err> {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        do { try p.run() } catch { return .failure(Err("cannot run security")) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            return .failure(Err(p.terminationStatus == 44 ? "no Claude Code login found" : "keychain access denied"))
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let o = json["claudeAiOauth"] as? [String: Any],
              let token = o["accessToken"] as? String else { return .failure(Err("bad credential format")) }
        let exp = (o["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        return .success(Creds(token: token, expiresAt: exp, subscription: o["subscriptionType"] as? String))
    }

    static func fetch() async -> ProviderLimits {
        var out = ProviderLimits()
        let creds: Creds
        switch credentials() {
        case .failure(let e): out.error = e.msg; return out
        case .success(let c): creds = c
        }
        out.plan = creds.subscription
        // expiresAt in Keychain can lag behind Claude Code's in-memory refresh → still try; 401 handled below.
        let looksExpired = creds.expiresAt.map { $0 < Date() } ?? false
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.setValue("Bearer \(creds.token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else {
                out.error = (code == 401 || looksExpired) ? "token expired — run `claude` once to refresh" : "HTTP \(code)"
                return out
            }
            guard let j = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                out.error = "bad response"; return out
            }
            func lim(_ key: String, _ name: String) -> RateLimit? {
                guard let w = j[key] as? [String: Any], let u = w["utilization"] as? NSNumber else { return nil }
                return RateLimit(name: name, percent: u.doubleValue, resetsAt: parseDate(w["resets_at"] as? String))
            }
            if let l = lim("five_hour", "5h") { out.limits.append(l) }
            if let l = lim("seven_day", "Weekly") { out.limits.append(l) }
            // Model-scoped weekly limits (e.g. Opus / Fable) from the `limits` array.
            for item in (j["limits"] as? [[String: Any]]) ?? [] where (item["kind"] as? String) == "weekly_scoped" {
                let model = ((item["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String
                guard let pct = item["percent"] as? NSNumber else { continue }
                out.limits.append(RateLimit(name: "Weekly · \(model ?? "scoped")", percent: pct.doubleValue,
                                            resetsAt: parseDate(item["resets_at"] as? String)))
            }
            out.fetchedAt = Date()
        } catch {
            out.error = "offline"
        }
        return out
    }
}
