import SwiftUI

struct ProviderCard: View {
    let stats: ProviderStats
    let window: Window
    var limits: ProviderLimits? = nil
    @State private var expanded = false

    private var color: Color {
        let (r, g, b) = stats.provider.accent
        return Color(red: r, green: g, blue: b)
    }
    private var bd: TokenBreakdown { stats.stats(window) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let limits, !limits.limits.isEmpty { limitGauges(limits) }
            else if let err = limits?.error { Text("limits: \(err)").font(.system(size: 10.5)).foregroundStyle(.tertiary) }
            if stats.available {
                mainNumbers
                breakdownBar
                sourceList
                if expanded { modelList }
            } else {
                Text("No local data found")
                    .font(.system(size: 12)).foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(color.opacity(0.25), lineWidth: 1))
        )
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy(duration: 0.2)) { expanded.toggle() } }
    }

    private var header: some View {
        HStack(spacing: 8) {
            ProviderLogoView(provider: stats.provider, size: 13)
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .background(Circle().fill(color.opacity(0.15)))
            VStack(alignment: .leading, spacing: 0) {
                Text(stats.provider.displayName).font(.system(size: 13, weight: .semibold))
                Text(stats.provider.vendor).font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            Spacer()
            if let last = stats.lastActivity {
                Text(last.agoShort)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(expanded ? 90 : 0))
        }
    }

    private func limitGauges(_ l: ProviderLimits) -> some View {
        VStack(spacing: 5) {
            ForEach(l.limits) { lim in
                HStack(spacing: 8) {
                    Text(lim.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 84, alignment: .leading)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.08))
                            Capsule().fill(gaugeColor(lim.percent))
                                .frame(width: max(3, geo.size.width * CGFloat(min(lim.percent, 100)) / 100))
                        }
                    }
                    .frame(height: 7)
                    Text("\(Int(lim.percent.rounded()))%")
                        .font(.system(size: 12, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(gaugeColor(lim.percent))
                        .frame(width: 40, alignment: .trailing)
                    Text(lim.resetText)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 108, alignment: .trailing)
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
            }
            HStack(spacing: 6) {
                if let plan = l.plan {
                    Text(plan.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(1).foregroundStyle(.tertiary)
                }
                if let err = l.error {
                    Text("· stale: \(err)").font(.system(size: 9)).foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.3).opacity(0.8))
                        .lineLimit(1).minimumScaleFactor(0.8)
                } else if let t = l.fetchedAt, Date().timeIntervalSince(t) > 3600 {
                    Text("· as of \(t.agoShort)").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                Spacer()
            }
        }
        .padding(.vertical, 2)
    }

    private func gaugeColor(_ p: Double) -> Color {
        switch p {
        case 90...: return Color(red: 1.0, green: 0.35, blue: 0.35)
        case 70..<90: return Color(red: 1.0, green: 0.72, blue: 0.3)
        default: return color
        }
    }

    private var mainNumbers: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(bd.total.compact)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("tokens · \(bd.calls) calls")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(bd.cost.usd)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(color)
                    .monospacedDigit()
                Text("est. cost").font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            Sparkline(values: stats.daily, color: color)
                .frame(width: 76, height: 28)
        }
    }

    private var breakdownBar: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                let t = max(bd.total, 1)
                HStack(spacing: 1.5) {
                    seg(bd.input, t, geo.size.width, color)
                    seg(bd.output, t, geo.size.width, color.opacity(0.7))
                    seg(bd.cacheRead, t, geo.size.width, .white.opacity(0.22))
                    seg(bd.cacheWrite, t, geo.size.width, .white.opacity(0.4))
                }
            }
            .frame(height: 5)
            .clipShape(Capsule())
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                      alignment: .leading, spacing: 4) {
                legend("in", bd.input, color)
                legend("out", bd.output, color.opacity(0.7))
                legend("cache read", bd.cacheRead, .white.opacity(0.22))
                legend("cache write", bd.cacheWrite, .white.opacity(0.4))
            }
        }
    }

    @ViewBuilder
    private func seg(_ v: Int, _ total: Int, _ width: CGFloat, _ c: Color) -> some View {
        if v > 0 {
            Rectangle().fill(c).frame(width: max(1, width * CGFloat(v) / CGFloat(total)))
        }
    }

    private func legend(_ label: String, _ v: Int, _ c: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(c).frame(width: 6, height: 6)
            Text("\(label) \(v.compact)")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// Per-source split (Terminal / Desktop / Zed …) for the selected window.
    @ViewBuilder
    private var sourceList: some View {
        let sources = stats.sources(window)
        if !sources.isEmpty {
            let total = max(bd.total, 1)
            VStack(alignment: .leading, spacing: 5) {
                Divider().opacity(0.3)
                Text("SOURCES").font(.system(size: 9.5, weight: .bold)).foregroundStyle(.tertiary)
                // stacked bar
                GeometryReader { geo in
                    HStack(spacing: 1.5) {
                        ForEach(Array(sources.enumerated()), id: \.offset) { i, src in
                            Rectangle().fill(color.opacity(sourceOpacity(i)))
                                .frame(width: max(1, geo.size.width * CGFloat(src.stats.total) / CGFloat(total)))
                        }
                    }
                }
                .frame(height: 5).clipShape(Capsule())
                ForEach(Array(sources.enumerated()), id: \.offset) { i, src in
                    HStack(spacing: 6) {
                        Circle().fill(color.opacity(sourceOpacity(i))).frame(width: 7, height: 7)
                        Text(src.name).font(.system(size: 11.5)).lineLimit(1)
                        Spacer()
                        Text("\(Int((Double(src.stats.total) / Double(total) * 100).rounded()))%")
                            .font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                        Text(src.stats.total.compact)
                            .font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .trailing)
                        Text(src.stats.cost.usd)
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(color).frame(width: 64, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func sourceOpacity(_ i: Int) -> Double { [1.0, 0.6, 0.35, 0.22, 0.15][min(i, 4)] }

    private var modelList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().opacity(0.3)
            Text("MODELS · LAST 30D").font(.system(size: 9.5, weight: .bold)).foregroundStyle(.tertiary)
            let models = stats.byModel.sorted { $0.value.cost > $1.value.cost }.prefix(6)
            ForEach(Array(models), id: \.key) { model, b in
                HStack {
                    Text(model).font(.system(size: 11.5, design: .monospaced)).lineLimit(1)
                    Spacer()
                    Text(b.total.compact).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary)
                    Text(b.cost.usd).font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(color).frame(width: 64, alignment: .trailing)
                }
            }
        }
    }
}
