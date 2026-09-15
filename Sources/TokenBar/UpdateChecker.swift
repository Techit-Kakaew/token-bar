import Foundation
import AppKit
import CryptoKit

/// Compares the running version with the latest GitHub release and can install it in place:
/// download .dmg → verify sha256 (from the release's .sha256 asset) → mount → swap the app bundle →
/// strip quarantine + ad-hoc re-sign → relaunch.
@MainActor
final class UpdateChecker: ObservableObject {
    static let repo = "Techit-Kakaew/token-bar"

    enum Phase: Equatable { case idle, downloading(Double), verifying, installing, relaunching, failed(String) }

    @Published var latest: String?          // e.g. "0.4.1" when newer than current
    @Published var latestURL: URL?          // release page
    @Published var dmgURL: URL?
    @Published var shaURL: URL?
    @Published var checking = false
    @Published var phase: Phase = .idle

    var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    func autoCheck() {
        let last = UserDefaults.standard.object(forKey: "update.lastCheck") as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 86400 else { return }
        Task { await check(manual: false) }
    }

    /// Fetches the latest release; `force` treats it as newer regardless of version (testing).
    @discardableResult
    func check(manual: Bool, force: Bool = false) async -> Bool {
        checking = true; defer { checking = false }
        UserDefaults.standard.set(Date(), forKey: "update.lastCheck")
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = j["tag_name"] as? String else {
            if manual { alert(L("update.error"), info: nil, url: nil) }
            return false
        }
        let remote = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let page = (j["html_url"] as? String).flatMap(URL.init)
        let assets = (j["assets"] as? [[String: Any]]) ?? []
        func asset(_ suffix: String) -> URL? {
            assets.first { ($0["name"] as? String)?.hasSuffix(suffix) == true }
                .flatMap { ($0["browser_download_url"] as? String).flatMap(URL.init) }
        }
        if force || Self.isNewer(remote, than: current) {
            latest = remote; latestURL = page
            dmgURL = asset(".dmg"); shaURL = asset(".dmg.sha256")
            if manual { alertUpdate(remote) }
            return true
        } else {
            latest = nil
            if manual { alert(L("update.none %@", current), info: nil, url: nil) }
            return false
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

    // MARK: - In-app install

    /// Downloads, verifies and installs `latest` over the running bundle, then relaunches.
    func installUpdate() async {
        guard let dmgURL else { openReleasePage(); return }
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("tokenbar-update-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        do {
            // 1. download
            phase = .downloading(0)
            let dmg = work.appendingPathComponent("TokenBar.dmg")
            try await download(dmgURL, to: dmg) { [weak self] p in Task { @MainActor in self?.phase = .downloading(p) } }
            // 2. verify sha256 (mandatory when the release ships one)
            phase = .verifying
            if let shaURL {
                let (shaData, _) = try await URLSession.shared.data(from: shaURL)
                let expected = String(decoding: shaData, as: UTF8.self).split(separator: " ").first.map(String.init)?.lowercased() ?? ""
                let actual = SHA256.hash(data: try Data(contentsOf: dmg)).map { String(format: "%02x", $0) }.joined()
                guard !expected.isEmpty, expected == actual else { throw Err("checksum mismatch") }
            }
            // 3. mount
            phase = .installing
            let mount = work.appendingPathComponent("mnt", isDirectory: true)
            try? fm.createDirectory(at: mount, withIntermediateDirectories: true)
            try run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path])
            defer { _ = try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }
            let newApp = mount.appendingPathComponent("TokenBar.app")
            guard fm.fileExists(atPath: newApp.path) else { throw Err("TokenBar.app not found in image") }
            // 4. swap bundles (stage next to the target so it's the same volume, keep the old one until success)
            let target = Bundle.main.bundleURL
            let dir = target.deletingLastPathComponent()
            guard fm.isWritableFile(atPath: dir.path) else { throw Err("cannot write to \(dir.path)") }
            let staged = dir.appendingPathComponent(".TokenBar-\(latest ?? "new").app")
            let backup = dir.appendingPathComponent(".TokenBar-previous.app")
            try? fm.removeItem(at: staged); try? fm.removeItem(at: backup)
            try run("/bin/cp", ["-R", newApp.path, staged.path])
            try run("/usr/bin/xattr", ["-cr", staged.path])
            _ = try? run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", staged.path])
            try fm.moveItem(at: target, to: backup)
            do { try fm.moveItem(at: staged, to: target) } catch {
                try? fm.moveItem(at: backup, to: target); throw error
            }
            try? fm.removeItem(at: backup)
            try? run("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister", ["-f", target.path])
            // 5. relaunch
            phase = .relaunching
            let script = "sleep 1; /usr/bin/open \"\(target.path)\""
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh"); p.arguments = ["-c", script]
            try p.run()
            try? await Task.sleep(for: .milliseconds(300))
            NSApp?.terminate(nil)
            exit(0)
        } catch {
            phase = .failed((error as? Err)?.msg ?? error.localizedDescription)
        }
    }

    func openReleasePage() { if let u = latestURL { NSWorkspace.shared.open(u) } }

    struct Err: Error { let msg: String; init(_ m: String) { msg = m } }

    private func download(_ url: URL, to dest: URL, progress: @escaping (Double) -> Void) async throws {
        let (bytes, resp) = try await URLSession.shared.bytes(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw Err("download failed") }
        let total = Double(resp.expectedContentLength)
        var data = Data(); data.reserveCapacity(Int(max(total, 0)))
        var lastReport = 0
        for try await b in bytes {
            data.append(b)
            if total > 0, data.count - lastReport > 200_000 { lastReport = data.count; progress(Double(data.count) / total) }
        }
        try data.write(to: dest)
        progress(1)
    }

    @discardableResult
    private func run(_ exe: String, _ args: [String]) throws -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        let out = Pipe(), err = Pipe(); p.standardOutput = out; p.standardError = err
        try p.run(); p.waitUntilExit()
        let o = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard p.terminationStatus == 0 else {
            let e = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw Err("\(URL(fileURLWithPath: exe).lastPathComponent) failed: \(e.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return o
    }

    // MARK: - Alerts

    private func alertUpdate(_ remote: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert(); a.messageText = L("update.available %@", remote); a.informativeText = L("update.current %@", current)
        a.addButton(withTitle: L("Update now")); a.addButton(withTitle: L("Release page")); a.addButton(withTitle: L("Later"))
        switch a.runModal() {
        case .alertFirstButtonReturn: Task { await installUpdate() }
        case .alertSecondButtonReturn: openReleasePage()
        default: break
        }
    }

    private func alert(_ title: String, info: String?, url: URL?) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert(); a.messageText = title; a.informativeText = info ?? ""
        if let url { a.addButton(withTitle: L("Download")); a.addButton(withTitle: L("Later")) } else { a.addButton(withTitle: "OK") }
        if a.runModal() == .alertFirstButtonReturn, let url { NSWorkspace.shared.open(url) }
    }
}
