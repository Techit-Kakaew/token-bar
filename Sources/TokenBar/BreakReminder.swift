import Foundation
import UserNotifications

/// Detects continuous AI usage streaks from event timestamps and nudges the user to take a break.
@MainActor
final class BreakReminder: ObservableObject {
    @Published var enabled: Bool = UserDefaults.standard.object(forKey: "break.enabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(enabled, forKey: "break.enabled"); if enabled { requestPermission() } }
    }
    /// Minutes of continuous use before the first reminder.
    @Published var thresholdMinutes: Int = UserDefaults.standard.object(forKey: "break.threshold") as? Int ?? 90 {
        didSet { UserDefaults.standard.set(thresholdMinutes, forKey: "break.threshold") }
    }
    /// Minutes between repeat reminders while the streak continues.
    @Published var repeatMinutes: Int = UserDefaults.standard.object(forKey: "break.repeat") as? Int ?? 45 {
        didSet { UserDefaults.standard.set(repeatMinutes, forKey: "break.repeat") }
    }
    /// Gap (minutes) with no calls that ends a streak.
    @Published var idleGapMinutes: Int = UserDefaults.standard.object(forKey: "break.idle") as? Int ?? 15 {
        didSet { UserDefaults.standard.set(idleGapMinutes, forKey: "break.idle") }
    }

    struct Streak { let start: Date; let last: Date; var duration: TimeInterval { last.timeIntervalSince(start) } }
    @Published var streak: Streak?
    @Published var permissionDenied = false

    private var lastNotified: Date?
    private var notifiedStreakStart: Date?

    /// UNUserNotificationCenter crashes outside a real .app bundle (e.g. `swift run`, --snapshot).
    private static let canNotify = Bundle.main.bundleIdentifier != nil

    init() {}   // permission is requested from onboarding or when the user toggles a reminder on

    func requestPermission() {
        guard Self.canNotify else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in self.permissionDenied = !granted }
        }
    }

    /// `timestamps`: event times from the last ~24h (any order).
    nonisolated static func computeStreak(_ timestamps: [Date], idleGap: TimeInterval, now: Date = Date()) -> Streak? {
        let sorted = timestamps.sorted(by: >)
        guard let last = sorted.first, now.timeIntervalSince(last) < idleGap else { return nil }
        var start = last
        for t in sorted.dropFirst() {
            if start.timeIntervalSince(t) > idleGap { break }
            start = t
        }
        return Streak(start: start, last: last)
    }

    func update(with timestamps: [Date]) {
        let s = Self.computeStreak(timestamps, idleGap: TimeInterval(idleGapMinutes * 60))
        streak = s
        guard enabled, let s else { notifiedStreakStart = nil; return }
        let mins = Int(s.duration / 60)
        guard mins >= thresholdMinutes else { return }
        let isNewStreak = notifiedStreakStart != s.start
        let due = lastNotified.map { Date().timeIntervalSince($0) >= TimeInterval(repeatMinutes * 60) } ?? true
        guard isNewStreak || due else { return }
        notify(minutes: mins)
        lastNotified = Date()
        notifiedStreakStart = s.start
    }

    /// Debug: fire the break notification immediately (`TokenBar --notify-test`).
    func fireTest() { notify(minutes: 47) }

    private func notify(minutes: Int) {
        guard Self.canNotify else { return }
        let h = minutes / 60, m = minutes % 60
        let dur = h > 0 ? L("dur.hm", h, m) : L("dur.m", m)
        let content = UNMutableNotificationContent()
        content.title = L("break.title")
        content.body = L("break.body %@", dur)
        content.sound = .default
        let req = UNNotificationRequest(identifier: "tokenbar.break", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
