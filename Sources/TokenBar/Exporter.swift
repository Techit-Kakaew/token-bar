import Foundation
import AppKit

/// Builds CSV / Markdown exports from store data.
enum Exporter {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    /// Gregorian + POSIX locale so exports never pick up the Buddhist calendar from a Thai system locale.
    static func gregorian(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = format
        return f
    }
    private static let day = gregorian("yyyy-MM-dd")

    private static func csv(_ s: String) -> String {
        s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }

    // MARK: events

    static func eventsCSV(_ events: [UsageEvent]) -> String {
        var out = "timestamp,date,provider,source,project,model,input,output,cache_read,cache_write,total,cost_usd\n"
        for e in events.sorted(by: { $0.timestamp < $1.timestamp }) {
            out += [iso.string(from: e.timestamp), day.string(from: e.timestamp), e.provider.displayName,
                    csv(e.source), csv(e.project), csv(e.model),
                    "\(e.input)", "\(e.output)", "\(e.cacheRead)", "\(e.cacheWrite)", "\(e.total)",
                    String(format: "%.6f", Pricing.cost(e))].joined(separator: ",") + "\n"
        }
        return out
    }

    // MARK: daily

    static func dailyCSV(_ stats: [Provider: ProviderStats]) -> String {
        var out = "date,provider,tokens,cost_usd\n"
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for i in 0..<ProviderStats.days {
            let d = cal.date(byAdding: .day, value: i - (ProviderStats.days - 1), to: today)!
            for p in Provider.allCases {
                guard let s = stats[p], s.dailyTokens[i] > 0 else { continue }
                out += "\(day.string(from: d)),\(p.displayName),\(s.dailyTokens[i]),\(String(format: "%.4f", s.dailyCost[i]))\n"
            }
        }
        return out
    }

    // MARK: markdown report

    static func markdown(stats: [Provider: ProviderStats], window: Window, limits: [Provider: ProviderLimits]) -> String {
        let f = gregorian("yyyy-MM-dd HH:mm")
        var md = "# TokenBar report — \(window.rawValue)\n\n_Generated \(f.string(from: Date()))_\n\n"
        let providers = Provider.allCases.filter { stats[$0]?.available == true }

        md += "## Totals\n\n| Provider | Tokens | Input | Output | Cache read | Cache write | Calls | Est. cost |\n|---|---:|---:|---:|---:|---:|---:|---:|\n"
        var total = TokenBreakdown()
        for p in providers {
            let b = stats[p]!.stats(window)
            total.input += b.input; total.output += b.output; total.cacheRead += b.cacheRead
            total.cacheWrite += b.cacheWrite; total.cost += b.cost; total.calls += b.calls
            md += "| \(p.displayName) | \(b.total.compact) | \(b.input.compact) | \(b.output.compact) | \(b.cacheRead.compact) | \(b.cacheWrite.compact) | \(b.calls) | \(b.cost.usd) |\n"
        }
        md += "| **Total** | **\(total.total.compact)** | \(total.input.compact) | \(total.output.compact) | \(total.cacheRead.compact) | \(total.cacheWrite.compact) | \(total.calls) | **\(total.cost.usd)** |\n\n"

        func section(_ title: String, _ rows: [(String, Provider, TokenBreakdown)]) {
            guard !rows.isEmpty else { return }
            md += "## \(title)\n\n| Name | Provider | Tokens | Est. cost |\n|---|---|---:|---:|\n"
            for (n, p, b) in rows.sorted(by: { $0.2.total > $1.2.total }).prefix(15) {
                md += "| \(n) | \(p.displayName) | \(b.total.compact) | \(b.cost.usd) |\n"
            }
            md += "\n"
        }
        section("Projects", providers.flatMap { p in stats[p]!.projects(window).map { ($0.name, p, $0.stats) } })
        section("Models (last 30d)", providers.flatMap { p in stats[p]!.byModel.map { ($0.key, p, $0.value) } })
        section("Sources", providers.flatMap { p in stats[p]!.sources(window).map { ($0.name, p, $0.stats) } })

        let lim = providers.compactMap { p in limits[p].map { (p, $0) } }.filter { !$0.1.limits.isEmpty }
        if !lim.isEmpty {
            md += "## Rate limits\n\n| Provider | Window | Used | Resets |\n|---|---|---:|---|\n"
            for (p, l) in lim { for r in l.limits { md += "| \(p.displayName) | \(r.name) | \(Int(r.percent))% | \(r.resetText) |\n" } }
            md += "\n"
        }
        md += "_Costs are list-price equivalents (USD / 1M tokens), not billed amounts._\n"
        return md
    }

    // MARK: save

    @MainActor
    static func save(_ content: String, suggested: String, type: String) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggested
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [type == "csv" ? .commaSeparatedText : .plainText]
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            try? content.data(using: .utf8)?.write(to: url)
        }
    }

    static func stamp() -> String { day.string(from: Date()) }
}
