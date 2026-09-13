import XCTest
@testable import TokenBar

final class ParserTests: XCTestCase {
    private func fixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(name)")
    }

    func testClaudeDedupesAndMapsSourceProject() {
        let ev = ClaudeSource().parse(file: fixture("claude.jsonl"))
        XCTAssertEqual(ev.count, 2, "duplicate msg_1 lines collapse; <synthetic> is dropped")
        let a = ev[0]
        XCTAssertEqual(a.model, "claude-opus-5")
        XCTAssertEqual(a.input, 10); XCTAssertEqual(a.output, 100)
        XCTAssertEqual(a.cacheRead, 1000); XCTAssertEqual(a.cacheWrite, 200)
        XCTAssertEqual(a.total, 1310)
        XCTAssertEqual(a.source, "Terminal (CLI)"); XCTAssertEqual(a.project, "alpha")
        XCTAssertEqual(ev[1].source, "Zed / Agent SDK"); XCTAssertEqual(ev[1].project, "beta")
    }

    func testCodexSplitsCachedFromInputAndReadsMeta() {
        let ev = CodexSource().parse(file: fixture("codex.jsonl"))
        XCTAssertEqual(ev.count, 1, "token_count with info:null is skipped")
        let e = ev[0]
        XCTAssertEqual(e.model, "gpt-5.4")
        XCTAssertEqual(e.input, 200, "input_tokens minus cached")
        XCTAssertEqual(e.cacheRead, 500); XCTAssertEqual(e.output, 30)
        XCTAssertEqual(e.source, "VS Code"); XCTAssertEqual(e.project, "gamma")
    }

    func testGeminiChatFormat() {
        let ev = GeminiSource().parse(file: fixture("gemini.json"))
        XCTAssertEqual(ev.count, 1)
        XCTAssertEqual(ev[0].input, 120); XCTAssertEqual(ev[0].output, 55, "output + thoughts + tool")
        XCTAssertEqual(ev[0].cacheRead, 20); XCTAssertEqual(ev[0].model, "gemini-3-pro-preview")
    }

    func testOpenCodeMessage() {
        let ev = OpenCodeSource().parse(file: fixture("opencode.json"))
        XCTAssertEqual(ev.count, 1)
        XCTAssertEqual(ev[0].input, 300); XCTAssertEqual(ev[0].output, 75)
        XCTAssertEqual(ev[0].cacheRead, 1000); XCTAssertEqual(ev[0].cacheWrite, 50)
        XCTAssertEqual(ev[0].source, "OpenCode · anthropic")
        XCTAssertEqual(Int(ev[0].timestamp.timeIntervalSince1970), 1756713605)
    }

    func testPricingLongestPrefixAndCost() {
        XCTAssertEqual(Pricing.price(for: "claude-opus-5")?.input, 5)
        XCTAssertEqual(Pricing.price(for: "claude-fable-5-1")?.cacheRead, 0.25, "5-1 beats fable-5 prefix")
        XCTAssertEqual(Pricing.price(for: "gpt-5.4-mini")?.input, 0.4)
        let e = UsageEvent(provider: .claude, timestamp: Date(), model: "claude-opus-5",
                           input: 1_000_000, output: 0, cacheRead: 0, cacheWrite: 0)
        XCTAssertEqual(Pricing.cost(e), 5, accuracy: 0.0001)
        XCTAssertNil(Pricing.price(for: "totally-unknown-model"))
    }

    func testStreakDetection() {
        let now = Date()
        let close = [now, now.addingTimeInterval(-300), now.addingTimeInterval(-600)]
        XCTAssertEqual(Int(BreakReminder.computeStreak(close, idleGap: 900, now: now)!.duration), 600)
        let gapped = [now, now.addingTimeInterval(-2400), now.addingTimeInterval(-2700)]
        XCTAssertEqual(Int(BreakReminder.computeStreak(gapped, idleGap: 900, now: now)!.duration), 0)
        XCTAssertNil(BreakReminder.computeStreak([now.addingTimeInterval(-3600)], idleGap: 900, now: now), "idle → no streak")
    }

    func testVersionCompare() {
        XCTAssertTrue(UpdateChecker.isNewer("0.3.1", than: "0.3.0"))
        XCTAssertTrue(UpdateChecker.isNewer("1.0", than: "0.9.9"))
        XCTAssertFalse(UpdateChecker.isNewer("0.3.0", than: "0.3.0"))
        XCTAssertFalse(UpdateChecker.isNewer("0.2.9", than: "0.3"))
    }

    func testExportDatesAreGregorian() {
        let e = UsageEvent(provider: .codex, timestamp: Date(timeIntervalSince1970: 1_789_000_000), // 2026-09-10
                           model: "gpt-5.4", input: 1, output: 1, cacheRead: 0, cacheWrite: 0)
        let csv = Exporter.eventsCSV([e])
        XCTAssertTrue(csv.contains(",2026-09-"), "year must be 2026, never Buddhist 2569: \(csv)")
    }

    func testCompactFormatting() {
        XCTAssertEqual(1_234.compact, "1.2K"); XCTAssertEqual(2_500_000.compact, "2.5M")
        XCTAssertEqual(1_200_000_000.compact, "1.20B"); XCTAssertEqual(0.0.usd, "$0"); XCTAssertEqual(123.4.usd, "$123")
    }
}
