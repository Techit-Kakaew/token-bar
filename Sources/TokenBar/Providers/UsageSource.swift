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

/// Per-file parse cache keyed by (path, mtime, size), persisted to ~/Library/Caches. Only events inside
/// `FileCache.horizon` (last ~31 days) are kept individually; older ones are folded into ArchiveBucket
/// totals per (model, source, project), which is all the All-time views need. Keeps memory flat over time.
final class FileCache {
    struct Key: Hashable, Codable { let path: String; let mtime: Date; let size: Int }
    private struct Entry: Codable { let key: Key; var data: FileEvents }
    private var store: [String: Entry] = [:]
    private let lock = NSLock()
    private var dirty = false

    /// Detail horizon: one day before the oldest window/chart bucket so every 30-day view stays exact.
    static var horizon: Date {
        Calendar.current.date(byAdding: .day, value: -(ProviderStats.days + 1), to: Calendar.current.startOfDay(for: Date()))!
    }

    static let cacheURL: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "dev.techit.tokenbar.app", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("parse-cache-v4.json")
    }()

    init(persistent: Bool = true) {
        if persistent { Self.removeStaleCaches() }
        guard persistent, let data = try? Data(contentsOf: Self.cacheURL),
              var loaded = try? JSONDecoder().decode([String: Entry].self, from: data) else { return }
        let h = Self.horizon
        for (k, var e) in loaded where e.data.refold(horizon: h) { loaded[k] = e; dirty = true }
        store = loaded
    }

    func events(for url: URL, parse: (URL) -> [UsageEvent]) -> FileEvents {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let key = Key(path: url.path,
                      mtime: attrs?[.modificationDate] as? Date ?? .distantPast,
                      size: attrs?[.size] as? Int ?? 0)
        lock.lock()
        if let e = store[url.path], e.key == key { lock.unlock(); return e.data }
        lock.unlock()
        // autoreleasepool: JSONSerialization temporaries from a big file are released before the next file
        let data = autoreleasepool { FileEvents.split(parse(url), horizon: Self.horizon) }
        lock.lock(); store[url.path] = Entry(key: key, data: data); dirty = true; lock.unlock()
        return data
    }

    /// Delete parse caches from older schema versions (they are never read again).
    private static func removeStaleCaches() {
        let dir = cacheURL.deletingLastPathComponent()
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        for n in names where n.hasPrefix("parse-cache-v") && n != cacheURL.lastPathComponent {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(n))
        }
    }

    /// Write to disk if anything changed; drop entries whose files vanished.
    func persist() {
        lock.lock()
        guard dirty else { lock.unlock(); return }
        store = store.filter { FileManager.default.fileExists(atPath: $0.key) }
        let snapshot = store; dirty = false
        lock.unlock()
        if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: Self.cacheURL, options: .atomic) }
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
func forEachLine(of url: URL, containing needle: String, stopWhen: (() -> Bool)? = nil, _ body: ([String: Any]) -> Void) {
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
                        if stopWhen?() == true { return }
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
