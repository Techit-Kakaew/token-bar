import Foundation
import AppKit

/// Compares the running version with the latest GitHub release. Auto-checks once a day; manual check shows an alert.
@MainActor
final class UpdateChecker: ObservableObject {
    static let repo = "Techit-Kakaew/token-bar"
    @Published var latest: String?          // e.g. "0.3.1" when newer than current
    @Published var latestURL: URL?
    @Published var checking = false

    var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    func autoCheck() {
        let last = UserDefaults.standard.object(forKey: "update.lastCheck") as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 86400 else { return }
        Task { await check(manual: false) }
    }

    func check(manual: Bool) async {
        checking = true; defer { checking = false }
        UserDefaults.standard.set(Date(), forKey: "update.lastCheck")
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = j["tag_name"] as? String else {
            if manual { alert(L("update.error"), info: nil, url: nil) }
            return
        }
        let remote = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let url = (j["html_url"] as? String).flatMap(URL.init)
        if Self.isNewer(remote, than: current) {
            latest = remote; latestURL = url
            if manual { alert(L("update.available %@", remote), info: L("update.current %@", current), url: url) }
        } else {
            latest = nil
            if manual { alert(L("update.none %@", current), info: nil, url: nil) }
        }
    }

    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }, pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private func alert(_ title: String, info: String?, url: URL?) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert(); a.messageText = title; a.informativeText = info ?? ""
        if let url { a.addButton(withTitle: L("Download")); a.addButton(withTitle: L("Later")) } else { a.addButton(withTitle: "OK") }
        if a.runModal() == .alertFirstButtonReturn, let url { NSWorkspace.shared.open(url) }
    }
}
