import SwiftUI

/// Rows for conversations active in the last 15 minutes, with a context-window gauge.
struct LiveSessionsView: View {
    let sessions: [LiveSession]
    var compact = true

    private func color(_ p: Provider) -> Color { let (r, g, b) = p.accent; return Color(red: r, green: g, blue: b) }
    private func ctxColor(_ r: Double, _ base: Color) -> Color {
        r >= 0.9 ? Color(red: 1.0, green: 0.35, blue: 0.35) : (r >= 0.75 ? Color(red: 1.0, green: 0.72, blue: 0.3) : base)
    }
    private func dur(_ from: Date, _ to: Date) -> String {
        let m = Int(to.timeIntervalSince(from) / 60)
        return m >= 60 ? L("%dh %dm", m / 60, m % 60) : L("%dm", m)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(.green).frame(width: 6, height: 6)
                Text(L("LIVE SESSIONS")).font(.system(size: 9.5, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                Spacer()
                Text("\(sessions.count)").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
            }
            ForEach(sessions) { s in
                let c = color(s.provider)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        ProviderLogoView(provider: s.provider, size: 10).foregroundStyle(c).frame(width: 14)
                        Text(s.project).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Text("· \(s.source)").font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Circle().fill(s.state == .active ? .green : .gray).frame(width: 6, height: 6)
                        Text(s.state == .active ? L("active") : L("idle"))
                            .font(.system(size: 10)).foregroundStyle(s.state == .active ? .green : .secondary)
                        Text(s.last.agoShort).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                    }
                    HStack(spacing: 8) {
                        Text(L("context")).font(.system(size: 9.5)).foregroundStyle(.tertiary).frame(width: 44, alignment: .leading)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.primary.opacity(0.08))
                                Capsule().fill(ctxColor(s.contextRatio, c))
                                    .frame(width: max(3, g.size.width * CGFloat(min(s.contextRatio, 1))))
                            }
                        }.frame(height: 6)
                        Text("\(Int((s.contextRatio * 100).rounded()))%")
                            .font(.system(size: 11, weight: .bold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(ctxColor(s.contextRatio, c)).frame(width: 36, alignment: .trailing)
                        Text("\(s.contextTokens.compact) / \(s.contextWindow.compact)")
                            .font(.system(size: 9.5, design: .monospaced)).foregroundStyle(.tertiary)
                            .frame(width: 92, alignment: .trailing).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    HStack {
                        Text(s.model).font(.system(size: 9.5, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1)
                        Spacer()
                        Text(L("%d calls · %@ · %@", s.calls, s.cost.usd, dur(s.started, s.last)))
                            .font(.system(size: 9.5, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
                if s.id != sessions.last?.id { Divider().opacity(0.3) }
            }
        }
        .padding(12)
        .glassCard(accent: .green.opacity(0.6))
    }
}
