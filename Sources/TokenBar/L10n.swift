import Foundation

/// Minimal two-language table. Language = user override, else system (`th` → Thai), else English.
enum Lang: String, CaseIterable, Identifiable {
    case en, th
    var id: String { rawValue }
    var locale: Locale { Locale(identifier: rawValue == "th" ? "th_TH" : "en_US") }
}

enum L10n {
    /// Current language; set by UsageStore from the override / system.
    static var current: Lang = systemDefault()

    static func systemDefault() -> Lang {
        let first = Locale.preferredLanguages.first?.lowercased() ?? "en"
        return first.hasPrefix("th") ? .th : .en
    }

    static func resolve(override: String) -> Lang {
        Lang(rawValue: override) ?? systemDefault()
    }

    // key → (en, th)
    static let table: [String: (String, String)] = [
        // popover
        "tokens": ("tokens", "tokens"),
        "streak %@": ("streak %@", "ใช้ต่อเนื่อง %@"),
        "streak over %@": ("%@ straight — take a break?", "ใช้ต่อเนื่อง %@ — พักหน่อยไหม"),
        "Dashboard": ("Dashboard", "แดชบอร์ด"),
        "updated %@": ("updated %@", "อัปเดต %@"),
        "No local data found": ("No local data found", "ไม่พบข้อมูลในเครื่อง"),
        "nodata.hint": ("TokenBar reads ~/.claude/projects, ~/.codex/sessions and ~/.gemini/tmp. Use Claude Code, Codex CLI or Gemini CLI once and it will appear here.",
                        "TokenBar อ่านจาก ~/.claude/projects, ~/.codex/sessions และ ~/.gemini/tmp ใช้ Claude Code, Codex CLI หรือ Gemini CLI สักครั้งแล้วจะขึ้นที่นี่"),
        "limits: %@": ("limits: %@", "limit: %@"),
        "est. cost": ("est. cost", "ค่าใช้จ่ายประมาณ"),
        "tokens · %d calls": ("tokens · %d calls", "tokens · %d ครั้ง"),
        "SOURCES": ("SOURCES", "แหล่งที่มา"),
        "MODELS · LAST 30D": ("MODELS · LAST 30D", "โมเดล · 30 วันล่าสุด"),
        "in": ("in", "เข้า"), "out": ("out", "ออก"),
        "cache read": ("cache read", "cache อ่าน"), "cache write": ("cache write", "cache เขียน"),
        "· stale: %@": ("· stale: %@", "· ค้าง: %@"),
        "· as of %@": ("· as of %@", "· ณ %@"),
        // settings menu
        "Launch at login": ("Launch at login", "เปิดตอน Login"),
        "Show number in menu bar": ("Show number in menu bar", "แสดงตัวเลขบน menubar"),
        "Menu bar shows": ("Menu bar shows", "แสดงบน menubar"),
        "All providers": ("All providers", "รวมทุกเจ้า"),
        "Theme": ("Theme", "ธีม"),
        "System": ("System", "ตามระบบ"), "Light": ("Light", "สว่าง"), "Dark": ("Dark", "มืด"),
        "Language": ("Language", "ภาษา"),
        "Limit alert at": ("Limit alert at", "เตือน limit เมื่อถึง"),
        "Off (95% only)": ("Off (95%% only)", "ปิด (เฉพาะ 95%%)"),
        "%d%% + 95%%": ("%d%% + 95%%", "%d%% + 95%%"),
        "Break reminder": ("Break reminder", "เตือนให้พัก"),
        "Remind after": ("Remind after", "เตือนหลังใช้ต่อเนื่อง"),
        "Repeat every": ("Repeat every", "เตือนซ้ำทุก"),
        "Idle gap = break": ("Idle gap counts as a break", "ถือว่าพักเมื่อเว้น"),
        "%d min": ("%d min", "%d นาที"),
        "Open Notification settings…": ("Open Notification settings…", "เปิดสิทธิ์ Notification…"),
        // windows / limits / time
        "Today": ("Today", "วันนี้"), "7d": ("7d", "7 วัน"), "30d": ("30d", "30 วัน"), "All": ("All", "ทั้งหมด"),
        "5h": ("5h", "5 ชม."), "Weekly": ("Weekly", "รายสัปดาห์"),
        "Weekly · %@": ("Weekly · %@", "รายสัปดาห์ · %@"),
        "resetting": ("resetting", "กำลังรีเซ็ต"), "tmr": ("tmr", "พรุ่งนี้"),
        "%ds ago": ("%ds ago", "%d วิ. ที่แล้ว"), "%dm ago": ("%dm ago", "%d น. ที่แล้ว"),
        "%dh ago": ("%dh ago", "%d ชม. ที่แล้ว"), "%dd ago": ("%dd ago", "%d วันที่แล้ว"),
        "%dh %dm": ("%dh %dm", "%d ชม. %d น."), "%dm": ("%dm", "%d น."),
        // notifications
        "break.title": ("Time for a break ☕️", "พักสายตาหน่อย ☕️"),
        "break.body %@": ("You've been using AI for %@ straight. Stretch, drink some water, then come back.",
                          "ใช้ AI ต่อเนื่องมา %@ แล้ว ลุกยืดเส้น ดื่มน้ำ แล้วค่อยกลับมา"),
        "dur.hm": ("%d h %d min", "%d ชม. %d นาที"), "dur.m": ("%d min", "%d นาที"),
        "limit.critical %@ %@": ("%@ %@ limit almost full 🔴", "%@ %@ limit ใกล้เต็ม 🔴"),
        "limit.warn %@ %@ %d": ("%@ %@ limit at %d%% 🟠", "%@ %@ limit %d%% 🟠"),
        "limit.body %d": ("%d%% used", "ใช้ไป %d%% แล้ว"),
        "limit.body %d %@": ("%d%% used · resets in %@", "ใช้ไป %d%% แล้ว · reset อีก %@"),
        // dashboard
        "DAILY USAGE": ("DAILY USAGE", "การใช้งานรายวัน"),
        "click a bar to drill down": ("click a bar to drill down", "คลิกแท่งเพื่อดูรายวัน"),
        "Tokens": ("Tokens", "Tokens"), "Cost": ("Cost", "ค่าใช้จ่าย"),
        "PROJECTS": ("PROJECTS", "โปรเจกต์"), "MODELS": ("MODELS", "โมเดล"),
        "no data": ("no data", "ไม่มีข้อมูล"),
        "%d calls": ("%d calls", "%d ครั้ง"),
        "Input": ("Input", "Input"), "Output": ("Output", "Output"),
        "Cache read": ("Cache read", "Cache อ่าน"), "Cache write": ("Cache write", "Cache เขียน"),
        "Back to %@": ("Back to %@", "กลับไป %@"),
        "Export": ("Export", "ส่งออก"),
        "Events CSV": ("Events CSV", "CSV รายการ call"),
        "· last 30 days": ("· last 30 days", "· 30 วันล่าสุด"),
        "Daily summary CSV · last 30 days": ("Daily summary CSV · last 30 days", "CSV สรุปรายวัน · 30 วันล่าสุด"),
        "Markdown report · %@": ("Markdown report · %@", "รายงาน Markdown · %@"),
    ]
}

/// Localize `key` with optional format arguments.
func L(_ key: String, _ args: CVarArg...) -> String {
    let pair = L10n.table[key]
    let fmt = pair.map { L10n.current == .th ? $0.1 : $0.0 } ?? key
    return args.isEmpty ? fmt.replacingOccurrences(of: "%%", with: "%") : String(format: fmt, arguments: args)
}
