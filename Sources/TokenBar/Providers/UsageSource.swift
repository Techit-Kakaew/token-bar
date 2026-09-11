import Foundation

protocol UsageSource {
    var provider: Provider { get }
    var roots: [URL] { get }
    /// Return all usage events found in `file`.
    func parse(file: URL) -> [UsageEvent]
    /// File extension / name predicate.
    func matches(_ url: URL) -> Bool
}

extension UsageSource {
    var isAvailable: Bool {
        roots.contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    func enumerateFiles() -> [URL] {
        var out: [URL] = []
        let fm = FileManager.default
        for root in roots {
            guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                        options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let u as URL in e where matches(u) { out.append(u) }
        }
        return out
    }
}

/// Per-file parse cache keyed by (path, mtime, size). Cheap incremental refresh.
final class FileCache {
    struct Key: Hashable { let path: String; let mtime: Date; let size: Int }
    private var store: [String: (Key, [UsageEvent])] = [:]
    private let lock = NSLock()

    func events(for url: URL, parse: (URL) -> [UsageEvent]) -> [UsageEvent] {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let key = Key(path: url.path,
                      mtime: attrs?[.modificationDate] as? Date ?? .distantPast,
                      size: attrs?[.size] as? Int ?? 0)
        lock.lock()
        if let (k, ev) = store[url.path], k == key { lock.unlock(); return ev }
        lock.unlock()
        let ev = parse(url)
        lock.lock(); store[url.path] = (key, ev); lock.unlock()
        return ev
    }
}

// MARK: - Helpers

let isoParser: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
let isoParserNoFrac: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

func parseDate(_ s: String?) -> Date? {
    guard let s else { return nil }
    return isoParser.date(from: s) ?? isoParserNoFrac.date(from: s)
}

func int(_ v: Any?) -> Int {
    switch v {
    case let i as Int: return i
    case let d as Double: return Int(d)
    case let n as NSNumber: return n.intValue
    default: return 0
    }
}

/// Iterate lines of a (possibly large) file without loading everything as String.
func forEachLine(of url: URL, containing needle: String, _ body: ([String: Any]) -> Void) {
    guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return }
    let needleBytes = Array(needle.utf8)
    data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
        guard let base = raw.baseAddress else { return }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var start = 0
        let n = raw.count
        for i in 0...n {
            if i == n || bytes[i] == 0x0A {
                if i > start {
                    let slice = UnsafeRawBufferPointer(rebasing: raw[start..<i])
                    if contains(slice, needleBytes),
                       let obj = try? JSONSerialization.jsonObject(with: Data(slice)) as? [String: Any] {
                        body(obj)
                    }
                }
                start = i + 1
            }
        }
    }
}

private func contains(_ hay: UnsafeRawBufferPointer, _ needle: [UInt8]) -> Bool {
    let n = hay.count, m = needle.count
    guard m > 0, n >= m else { return false }
    var i = 0
    while i <= n - m {
        if hay[i] == needle[0] {
            var j = 1
            while j < m && hay[i + j] == needle[j] { j += 1 }
            if j == m { return true }
        }
        i += 1
    }
    return false
}

/// "/Users/x/Desktop/works/foo" → "foo"
func projectName(_ cwd: String?) -> String {
    guard let cwd, !cwd.isEmpty else { return "—" }
    let name = URL(fileURLWithPath: cwd).lastPathComponent
    return name.isEmpty ? "—" : name
}
