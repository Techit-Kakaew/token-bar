import SwiftUI

/// Animated fire around an icon. `level` 0…1+ = streak / threshold.
/// Stages: <0.25 ember · 0.25 small flame · 0.5 flame + glow · 0.75 bigger, faster · ≥1 blaze (red) with pulsing glow.
struct FlameBadge<Icon: View>: View {
    let level: Double
    var size: CGFloat = 26
    @ViewBuilder var icon: () -> Icon
    @Environment(\.isSnapshot) private var isSnapshot

    private var stage: Int { level >= 1 ? 4 : level >= 0.75 ? 3 : level >= 0.5 ? 2 : level >= 0.25 ? 1 : 0 }
    private var hot: Color { stage >= 4 ? Color(red: 1.0, green: 0.30, blue: 0.25) : Color(red: 1.0, green: 0.55, blue: 0.20) }
    private var warm: Color { stage >= 4 ? Color(red: 1.0, green: 0.60, blue: 0.20) : Color(red: 1.0, green: 0.80, blue: 0.30) }
    private var speed: Double { [0, 1.2, 1.6, 2.2, 3.0][stage] }
    private var intensity: Double { [0, 0.45, 0.7, 0.9, 1.0][stage] }

    var body: some View {
        if stage == 0 || isSnapshot {
            staticBody
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate * speed
                ZStack {
                    // glow
                    Circle()
                        .fill(hot.opacity(0.35 * intensity * (0.8 + 0.2 * sin(t * 2.1))))
                        .frame(width: size * (1.6 + 0.15 * sin(t * 1.7)), height: size * (1.6 + 0.15 * sin(t * 1.7)))
                        .blur(radius: size * 0.35)
                    // flames: three tongues with independent flicker
                    ForEach(0..<3, id: \.self) { i in
                        let phase = Double(i) * 2.1
                        let flick = 0.85 + 0.15 * sin(t * (2.3 + Double(i) * 0.4) + phase)
                        Image(systemName: "flame.fill")
                            .font(.system(size: size * (0.9 + 0.25 * intensity) * flick))
                            .foregroundStyle(
                                LinearGradient(colors: [warm, hot, hot.opacity(0.0)], startPoint: .bottom, endPoint: .top))
                            .offset(x: CGFloat(i - 1) * size * 0.28 + CGFloat(sin(t * 3 + phase)) * size * 0.05,
                                    y: -size * 0.35 - CGFloat(0.06 * sin(t * 2.7 + phase)) * size)
                            .opacity(0.55 * intensity + 0.15 * sin(t * 1.9 + phase))
                            .blur(radius: 0.6)
                    }
                    // the icon itself, on a warm disc
                    Circle().fill(.black.opacity(0.35)).frame(width: size, height: size)
                    icon()
                }
                .frame(width: size * 2, height: size * 2)
            }
        }
    }

    private var staticBody: some View {
        ZStack {
            if stage > 0 {
                Circle().fill(hot.opacity(0.3 * intensity)).frame(width: size * 1.6, height: size * 1.6).blur(radius: size * 0.35)
                Image(systemName: "flame.fill").font(.system(size: size * 1.1)).foregroundStyle(hot.opacity(0.7))
                    .offset(y: -size * 0.35)
            }
            Circle().fill(.black.opacity(0.35)).frame(width: size, height: size)
            icon()
        }
        .frame(width: size * 2, height: size * 2)
    }
}
