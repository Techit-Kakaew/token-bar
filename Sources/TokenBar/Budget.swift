import Foundation
import UserNotifications

/// Spend budgets (list-price USD) for today and the last 7 days, with 80% / 100% notifications.
@MainActor
final class Budget: ObservableObject {
    static let presets: [Double] = [0, 5, 10, 20, 50, 100, 200, 500]

    @Published var daily: Double = UserDefaults.standard.double(forKey: "budget.daily") {
        didSet { UserDefaults.standard.set(daily, forKey: "budget.daily") }
    }
    @Published var weekly: Double = UserDefaults.standard.double(forKey: "budget.weekly") {
        didSet { UserDefaults.standard.set(weekly, forKey: "budget.weekly") }
    }

    struct Status { let spent: Double; let limit: Double; var ratio: Double { limit > 0 ? spent / limit : 0 } }
    @Published private(set) var today: Status?
    @Published private(set) var week: Status?

    private var fired = Set<String>()
    private static let canNotify = Bundle.main.bundleIdentifier != nil

    func update(todaySpend: Double, weekSpend: Double) {
        today = daily > 0 ? Status(spent: todaySpend, limit: daily) : nil
        week = weekly > 0 ? Status(spent: weekSpend, limit: weekly) : nil
        let cal = Calendar.current
        let dayKey = cal.startOfDay(for: Date()).timeIntervalSince1970
        let weekKey = cal.component(.weekOfYear, from: Date())
        if let t = today { check(t, scope: "day", period: L("Today"), cycle: "\(dayKey)") }
        if let w = week { check(w, scope: "week", period: L("7d"), cycle: "\(weekKey)") }
    }

    private func check(_ s: Status, scope: String, period: String, cycle: String) {
        for pct in [100, 80] where s.ratio * 100 >= Double(pct) {
            let key = "\(scope)|\(pct)|\(cycle)"
            if fired.contains(key) { break }
            fired.insert(key); notify(s, pct: pct, period: period); break
        }
    }

    private func notify(_ s: Status, pct: Int, period: String) {
        guard Self.canNotify else { return }
        let c = UNMutableNotificationContent()
        c.title = pct >= 100 ? L("budget.over %@", period) : L("budget.warn %@ %d", period, pct)
        c.body = L("budget.body %@ %@", s.spent.usd, s.limit.usd)
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "tokenbar.budget.\(period)", content: c, trigger: nil))
    }
}
