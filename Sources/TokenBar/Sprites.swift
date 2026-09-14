import AppKit

/// RunCat-style menu-bar sprites: monochrome template frames, looped at a speed that follows the streak.
/// Built-in frames are authored as ASCII grids (`#` = ink) so there are no third-party assets.
/// Custom sprites: drop `frame0.png, frame1.png, …` (black + alpha, ~18×14 pt) into
/// `~/.config/tokenbar/sprites/<name>/` and pick the name in settings.
enum Sprites {
    struct Sheet { let name: String; let frames: [NSImage] }

    // MARK: built-in pixel cat (16×12), 5-frame run cycle

    private static let cat: [[String]] = [
        [
            "..............#..#..",
            "..............######",
            ".#............###.##",
            "..#....#############",
            "...#..##############",
            "....################",
            "....###############.",
            ".....#############..",
            "......###########...",
            "......##.......##...",
            ".....##.........##..",
            "....##...........##.",
        ],
        [
            "..............#..#..",
            "..............######",
            ".#............###.##",
            "..#....#############",
            "...#..##############",
            "....################",
            "....###############.",
            ".....#############..",
            "......###########...",
            ".......##.....##....",
            "......##.......##...",
            "......#.........#...",
        ],
        [
            "..............#..#..",
            "..............######",
            ".#............###.##",
            "..#....#############",
            "...#..##############",
            "....################",
            "....###############.",
            ".....#############..",
            "......###########...",
            "........##...##.....",
            "........##...##.....",
            ".......##.....##....",
        ],
        [
            "..............#..#..",
            "..............######",
            ".#............###.##",
            "..#....#############",
            "...#..##############",
            "....################",
            "....###############.",
            ".....#############..",
            "......###########...",
            ".......##.....##....",
            "........#.....#.....",
            "........#.....#.....",
        ],
        [
            "..............#..#..",
            "..............######",
            ".#............###.##",
            "..#....#############",
            "...#..##############",
            "....################",
            "....###############.",
            ".....#############..",
            "......###########...",
            "......##.......##...",
            ".....##.........##..",
            "....##...........##.",
        ],
    ]

    static let builtin: Sheet = Sheet(name: "cat", frames: cat.map { render(grid: $0) })

    // MARK: pixel fire (16×18), 6 frames. '#' outer (red/orange), '+' mid (orange), '*' core (yellow).

    static let pixelFire: [[String]] = [
        [
            "................",
            ".......#........",
            "......##........",
            "......###.......",
            ".....####....#..",
            ".....####...##..",
            "....######..##..",
            "....######.###..",
            "...#######+###..",
            "...######+++##..",
            "..######++++##..",
            "..#####+++++###.",
            "..####++****++#.",
            ".#####+*****++#.",
            ".####++******+##",
            ".####+*******+##",
            "..###++*****++#.",
            "...####+++++###.",
        ],
        [
            "................",
            "................",
            "..........#.....",
            "......#...##....",
            ".....##...##....",
            ".....###.###....",
            "....######......",
            "....#######.#...",
            "...#######++##..",
            "...######++++#..",
            "..#######++++##.",
            "..#####+++++###.",
            "..####++****++#.",
            ".####++******+#.",
            ".####+*******+##",
            ".###++*******+##",
            "..###++*****++#.",
            "...####+++++###.",
        ],
        [
            "........#.......",
            "........#.......",
            ".......##.......",
            ".......###......",
            "......####......",
            "..#...####......",
            "..##.#####......",
            "..########..#...",
            "..########+##...",
            "..#######+++##..",
            "..######+++++#..",
            "..#####++++++##.",
            "..####++*****+#.",
            ".####++******+#.",
            ".###++********##",
            ".###+*********##",
            "..##++*******+#.",
            "...####++++++##.",
        ],
        [
            "................",
            ".....#..........",
            ".....##.........",
            ".....###........",
            ".....####.......",
            "....#####...#...",
            "....######.##...",
            "....##########..",
            "...#######+###..",
            "...######+++##..",
            "..######++++###.",
            "..#####+++++###.",
            "..####++****++#.",
            ".####++******++.",
            ".####+*******+##",
            ".###++*******+##",
            "..###++*****++#.",
            "...####+++++###.",
        ],
        [
            "................",
            "................",
            "...........#....",
            "...........##...",
            "......#...###...",
            ".....##..####...",
            ".....########...",
            "....#########...",
            "....######++##..",
            "...######++++#..",
            "..######+++++##.",
            "..#####++++++##.",
            "..####++*****+#.",
            ".####++******+#.",
            ".###++*******+##",
            ".###+********+##",
            "..###++*****++#.",
            "...####+++++###.",
        ],
        [
            "................",
            "......#.........",
            "......##........",
            ".....###........",
            ".....####.......",
            "....#####.......",
            "....######..#...",
            "...#######.##...",
            "...#######+###..",
            "...######+++##..",
            "..######++++##..",
            "..#####+++++###.",
            "..####++****++#.",
            ".####++******+#.",
            ".####+*******+##",
            ".###++*******+##",
            "..###++*****++#.",
            "...####+++++###.",
        ],
    ]

    /// Renders a 3-tone fire grid. `stage` 1…4 shifts the palette from amber to red.
    static func renderFire(grid: [String], stage: Int) -> NSImage {
        let rows = grid.count, cols = grid.map(\.count).max() ?? 0
        let outer: NSColor = stage >= 4 ? NSColor(red: 0.95, green: 0.22, blue: 0.18, alpha: 1)
                          : stage >= 3 ? NSColor(red: 1.0, green: 0.40, blue: 0.15, alpha: 1)
                          : stage >= 2 ? NSColor(red: 1.0, green: 0.52, blue: 0.15, alpha: 1)
                          : NSColor(red: 1.0, green: 0.65, blue: 0.22, alpha: 1)
        let mid = NSColor(red: 1.0, green: 0.70, blue: 0.25, alpha: 1)
        let core = NSColor(red: 1.0, green: 0.93, blue: 0.55, alpha: 1)
        let img = NSImage(size: NSSize(width: cols, height: rows), flipped: true) { rect in
            guard let g = NSGraphicsContext.current?.cgContext else { return false }
            g.setShouldAntialias(false)
            for (y, line) in grid.enumerated() {
                for (x, ch) in line.enumerated() {
                    switch ch {
                    case "#": g.setFillColor(outer.cgColor)
                    case "+": g.setFillColor(mid.cgColor)
                    case "*": g.setFillColor(core.cgColor)
                    default: continue
                    }
                    g.fill(CGRect(x: CGFloat(x), y: CGFloat(y), width: 1, height: 1))
                }
            }
            return true
        }
        img.isTemplate = false
        return img
    }

    private static var fireCache: [Int: [NSImage]] = [:]
    static func fireFrames(stage: Int) -> [NSImage] {
        if let c = fireCache[stage] { return c }
        let f = pixelFire.map { renderFire(grid: $0, stage: stage) }
        fireCache[stage] = f
        return f
    }

    /// Renders an ASCII grid into a template NSImage (1 cell = 1 pt, drawn crisp at any scale).
    static func render(grid: [String]) -> NSImage {
        let rows = grid.count, cols = grid.map(\.count).max() ?? 0
        let img = NSImage(size: NSSize(width: cols, height: rows), flipped: true) { rect in
            guard let g = NSGraphicsContext.current?.cgContext else { return false }
            g.setShouldAntialias(false)
            g.setFillColor(NSColor.black.cgColor)
            for (y, line) in grid.enumerated() {
                for (x, ch) in line.enumerated() where ch == "#" {
                    g.fill(CGRect(x: CGFloat(x), y: CGFloat(y), width: 1, height: 1))
                }
            }
            return true
        }
        img.isTemplate = true
        return img
    }

    // MARK: custom sheets

    static var customDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/tokenbar/sprites")
    }

    static func availableNames() -> [String] {
        let custom = (try? FileManager.default.contentsOfDirectory(atPath: customDir.path))?.sorted() ?? []
        return ["cat"] + custom.filter { !$0.hasPrefix(".") }
    }

    private static var cache: [String: Sheet] = [:]

    static func sheet(named name: String) -> Sheet {
        if name == "cat" { return builtin }
        if let c = cache[name] { return c }
        let dir = customDir.appendingPathComponent(name)
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0.lowercased().hasSuffix(".png") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let frames = files.compactMap { NSImage(contentsOf: dir.appendingPathComponent($0)) }
        for f in frames { f.isTemplate = true; f.size = NSSize(width: f.size.width * 18 / max(f.size.height, 1), height: 18) }
        let sheet = frames.isEmpty ? builtin : Sheet(name: name, frames: frames)
        cache[name] = sheet
        return sheet
    }

    /// Frame interval for a streak level (0…1+): idle 0.5 s → blazing 0.07 s.
    static func interval(level: Double) -> TimeInterval {
        let l = min(max(level, 0), 1.2)
        return 0.5 - 0.36 * l
    }
}
