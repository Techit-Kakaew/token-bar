import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject var store: UsageStore
    @Environment(\.isSnapshot) private var isSnapshot
    @State private var metric: Metric = .tokens
    @State private var chartRange = 30

    enum Metric: String, CaseIterable, Identifiable { case tokens = "Tokens", cost = "Cost"; var id: String { rawValue } }

    private func color(_ p: Provider) -> Color { let (r, g, b) = p.accent; return Color(red: r, green: g, blue: b) }
    private var providers: [Provider] { Provider.allCases.filter { store.stats[$0]?.available == true } }

    var body: some View {
        Group {
            if isSnapshot { content } else { ScrollView { content } }
        }
        .frame(minWidth: 860, minHeight: 560)
        .background(Color(red: 0.08, green: 0.08, blue: 0.10))
        .preferredColorScheme(.dark)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            chartCard
            HStack(alignment: .top, spacing: 14) {
                listCard("PROJECTS", icon: "folder", rows: mergedRows { $0.projects(store.window) })
                listCard("MODELS", icon: "cpu", rows: modelRows)
                listCard("SOURCES", icon: "app.connected.to.app.below.fill", rows: mergedRows { $0.sources(store.window) })
            }
            providerRow
        }
        .padding(22)
    }

    // MARK: header

    private var header: some View {
        HStack(alignment: .lastTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("TOKENBAR · DASHBOARD").font(.system(size: 11, weight: .heavy)).tracking(2).foregroundStyle(.secondary)
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text(store.totalTokens.compact).font(.system(size: 40, weight: .black, design: .rounded)).contentTransition(.numericText())
                    Text("tokens").font(.system(size: 14)).foregroundStyle(.tertiary)
                    Text("≈ \(store.totalCost.usd)").font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 10) {
                ForEach(providers) { p in
                    let b = store.stats[p]?.stats(store.window) ?? TokenBreakdown()
                    HStack(spacing: 6) {
                        Circle().fill(color(p)).frame(width: 8, height: 8)
                        Text(p.displayName).font(.system(size: 12, weight: .medium))
                        Text(b.total.compact).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                        Text(b.cost.usd).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(color(p))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(.white.opacity(0.05)))
                }
            }
            if !isSnapshot {
                Picker("", selection: $store.window) {
                    ForEach(Window.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).frame(width: 220)
            } else {
                Text(store.window.rawValue).font(.system(size: 12, weight: .semibold)).padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.1)))
            }
        }
    }

    // MARK: chart

    struct DayPoint: Identifiable {
        let id = UUID(); let day: Date; let provider: Provider; let tokens: Int; let cost: Double
    }

    private var points: [DayPoint] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var out: [DayPoint] = []
        for p in providers {
            guard let s = store.stats[p] else { continue }
            for i in (ProviderStats.days - chartRange)..<ProviderStats.days {
                let day = cal.date(byAdding: .day, value: i - (ProviderStats.days - 1), to: today)!
                out.append(DayPoint(day: day, provider: p, tokens: s.dailyTokens[i], cost: s.dailyCost[i]))
            }
        }
        return out
    }

    private var chartCard: some View {
        card {
            HStack {
                sectionTitle("DAILY USAGE", icon: "chart.bar.fill")
                Spacer()
                if !isSnapshot {
                    Picker("", selection: $chartRange) {
                        Text("7d").tag(7); Text("14d").tag(14); Text("30d").tag(30)
                    }.pickerStyle(.segmented).frame(width: 150)
                    Picker("", selection: $metric) {
                        ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).frame(width: 140)
                }
            }
            Chart(points) { pt in
                BarMark(
                    x: .value("Day", pt.day, unit: .day),
                    y: .value(metric.rawValue, metric == .tokens ? Double(pt.tokens) : pt.cost)
                )
                .foregroundStyle(by: .value("Provider", pt.provider.displayName))
                .cornerRadius(3)
            }
            .chartForegroundStyleScale(
                domain: providers.map(\.displayName),
                range: providers.map(color)
            )
            .chartYAxis {
                AxisMarks(position: .leading) { v in
                    AxisGridLine().foregroundStyle(.white.opacity(0.06))
                    AxisValueLabel {
                        if let d = v.as(Double.self) {
                            Text(metric == .tokens ? Int(d).compact : d.usd)
                                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: chartRange > 14 ? 5 : (chartRange > 7 ? 2 : 1))) { v in
                    AxisValueLabel(centered: true) {
                        if let d = v.as(Date.self) {
                            Text(d, format: .dateTime.day().month(.abbreviated))
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartLegend(position: .top, alignment: .trailing)
            .frame(height: 220)
        }
    }

    // MARK: lists

    struct Row: Identifiable { let id: String; let name: String; let stats: TokenBreakdown; let provider: Provider? }

    /// Merge the same key across providers (e.g. one project used with both Claude and Codex).
    private func mergedRows(_ pick: (ProviderStats) -> [(name: String, stats: TokenBreakdown)]) -> [Row] {
        var acc: [String: (TokenBreakdown, Set<Provider>)] = [:]
        for p in providers {
            guard let s = store.stats[p] else { continue }
            for (name, b) in pick(s) {
                var cur = acc[name] ?? (TokenBreakdown(), [])
                cur.0.input += b.input; cur.0.output += b.output; cur.0.cacheRead += b.cacheRead
                cur.0.cacheWrite += b.cacheWrite; cur.0.cost += b.cost; cur.0.calls += b.calls
                cur.1.insert(p)
                acc[name] = cur
            }
        }
        return acc.map { Row(id: $0.key, name: $0.key, stats: $0.value.0, provider: $0.value.1.count == 1 ? $0.value.1.first : nil) }
            .sorted { $0.stats.total > $1.stats.total }
    }

    private var modelRows: [Row] {
        // byModel is last-30d; fine for a dashboard overview.
        var rows: [Row] = []
        for p in providers {
            for (m, b) in store.stats[p]?.byModel ?? [:] { rows.append(Row(id: m, name: m, stats: b, provider: p)) }
        }
        return rows.sorted { $0.stats.cost > $1.stats.cost }
    }

    private func listCard(_ title: String, icon: String, rows: [Row]) -> some View {
        card {
            sectionTitle(title, icon: icon)
            if rows.isEmpty {
                Text("no data").font(.system(size: 12)).foregroundStyle(.tertiary).padding(.vertical, 8)
            } else {
                let maxV = max(rows.first?.stats.total ?? 1, 1)
                VStack(spacing: 8) {
                    ForEach(rows.prefix(8)) { r in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                if let p = r.provider { Circle().fill(color(p)).frame(width: 7, height: 7) }
                                else { Circle().fill(.white.opacity(0.3)).frame(width: 7, height: 7) }
                                Text(r.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(r.stats.total.compact).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary)
                                Text(r.stats.cost.usd).font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(r.provider.map(color) ?? .white.opacity(0.7)).frame(width: 60, alignment: .trailing)
                            }
                            GeometryReader { g in
                                Capsule().fill((r.provider.map(color) ?? .white).opacity(0.35))
                                    .frame(width: max(2, g.size.width * CGFloat(r.stats.total) / CGFloat(maxV)))
                            }.frame(height: 3)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: provider detail row

    private var providerRow: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(providers) { p in
                if let s = store.stats[p] {
                    let b = s.stats(store.window)
                    card {
                        HStack {
                            ProviderLogoView(provider: p, size: 14).foregroundStyle(color(p))
                            Text(p.displayName).font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Text("\(b.calls) calls").font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
                        }
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                            stat("Input", b.input, color(p))
                            stat("Output", b.output, color(p).opacity(0.7))
                            stat("Cache read", b.cacheRead, .white.opacity(0.3))
                            stat("Cache write", b.cacheWrite, .white.opacity(0.5))
                        }
                        if let l = store.limits[p], !l.limits.isEmpty {
                            Divider().opacity(0.3)
                            ForEach(l.limits) { lim in
                                HStack {
                                    Text(lim.name).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                                    GeometryReader { g in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(.white.opacity(0.08))
                                            Capsule().fill(color(p)).frame(width: max(3, g.size.width * CGFloat(min(lim.percent, 100)) / 100))
                                        }
                                    }.frame(height: 6)
                                    Text("\(Int(lim.percent))%").font(.system(size: 11, weight: .bold, design: .rounded)).frame(width: 36, alignment: .trailing)
                                    Text(lim.resetText).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary).frame(width: 110, alignment: .trailing)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func stat(_ label: String, _ v: Int, _ c: Color) -> some View {
        GridRow {
            HStack(spacing: 6) { Circle().fill(c).frame(width: 6, height: 6); Text(label).font(.system(size: 11)).foregroundStyle(.secondary) }
            Text(v.compact).font(.system(size: 11.5, design: .monospaced)).gridColumnAlignment(.trailing)
        }
    }

    // MARK: chrome

    private func sectionTitle(_ t: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold))
            Text(t).font(.system(size: 10.5, weight: .heavy)).tracking(1.5)
        }
        .foregroundStyle(.secondary)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.07), lineWidth: 1)))
    }
}
