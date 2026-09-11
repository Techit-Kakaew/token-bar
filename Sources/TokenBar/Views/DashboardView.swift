import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject var store: UsageStore
    @Environment(\.isSnapshot) private var isSnapshot
    @State private var metric: Metric = .tokens
    @State private var chartRange = 30
    @State private var selectedDay: Date? = {
        // Debug: TOKENBAR_SNAPSHOT_DAY=N preselects N days ago (for --snapshot-dashboard).
        if let v = ProcessInfo.processInfo.environment["TOKENBAR_SNAPSHOT_DAY"], let n = Int(v) {
            return Calendar.current.date(byAdding: .day, value: -n, to: Calendar.current.startOfDay(for: Date()))
        }
        return nil
    }()

    private var dayEvents: [UsageEvent] {
        guard let d = selectedDay else { return [] }
        let cal = Calendar.current
        return store.recentEvents.filter { cal.isDate($0.timestamp, inSameDayAs: d) }
    }

    private var dayLabel: String {
        guard let d = selectedDay else { return "" }
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"
        return Calendar.current.isDateInToday(d) ? "Today" : f.string(from: d)
    }

    enum Metric: String, CaseIterable, Identifiable { case tokens = "Tokens", cost = "Cost"; var id: String { rawValue } }

    private func color(_ p: Provider) -> Color { let (r, g, b) = p.accent; return Color(red: r, green: g, blue: b) }
    private var providers: [Provider] { Provider.allCases.filter { store.stats[$0]?.available == true } }

    var body: some View {
        Group {
            if isSnapshot { content } else { ScrollView { content } }
        }
        .frame(minWidth: 860, minHeight: 560)
        .background {
            if isSnapshot { Color.clear } else { VisualEffect(material: .underWindowBackground).ignoresSafeArea() }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            chartCard
            if selectedDay != nil { dayBanner }
            HStack(alignment: .top, spacing: 14) {
                if selectedDay != nil {
                    listCard("PROJECTS · \(dayLabel)", icon: "folder", rows: dayRows(\.project))
                    listCard("MODELS · \(dayLabel)", icon: "cpu", rows: dayRows(\.model))
                    listCard("SOURCES · \(dayLabel)", icon: "app.connected.to.app.below.fill", rows: dayRows(\.source))
                } else {
                    listCard("PROJECTS", icon: "folder", rows: mergedRows { $0.projects(store.window) })
                    listCard("MODELS", icon: "cpu", rows: modelRows)
                    listCard("SOURCES", icon: "app.connected.to.app.below.fill", rows: mergedRows { $0.sources(store.window) })
                }
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
                    .background(Capsule().fill(.quaternary))
                }
            }
            if !isSnapshot {
                Picker("", selection: $store.window) {
                    ForEach(Window.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).frame(width: 220)
                exportMenu
            } else {
                Text(store.window.rawValue).font(.system(size: 12, weight: .semibold)).padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.primary.opacity(0.1)))
            }
        }
    }

    // MARK: export

    private var exportMenu: some View {
        Menu {
            Button("Events CSV\(selectedDay != nil ? " · \(dayLabel)" : " · last 30 days")") {
                let ev = selectedDay != nil ? dayEvents : store.recentEvents
                let suffix = selectedDay.map { Exporter_dayStamp($0) } ?? "30d"
                Exporter.save(Exporter.eventsCSV(ev), suggested: "tokenbar-events-\(suffix).csv", type: "csv")
            }
            Button("Daily summary CSV · last 30 days") {
                Exporter.save(Exporter.dailyCSV(store.stats), suggested: "tokenbar-daily-\(Exporter.stamp()).csv", type: "csv")
            }
            Button("Markdown report · \(store.window.rawValue)") {
                Exporter.save(Exporter.markdown(stats: store.stats, window: store.window, limits: store.limits),
                              suggested: "tokenbar-report-\(store.window.rawValue.lowercased())-\(Exporter.stamp()).md", type: "md")
            }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up").font(.system(size: 12, weight: .semibold))
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    private func Exporter_dayStamp(_ d: Date) -> String { Exporter.gregorian("yyyy-MM-dd").string(from: d) }

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
                Text("click a bar to drill down").font(.system(size: 10)).foregroundStyle(.tertiary)
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
                .opacity(selectedDay == nil || Calendar.current.isDate(pt.day, inSameDayAs: selectedDay!) ? 1 : 0.3)
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onTapGesture { loc in
                            guard let plot = proxy.plotFrame else { return }
                            let x = loc.x - geo[plot].origin.x
                            guard let d: Date = proxy.value(atX: x) else { return }
                            let day = Calendar.current.startOfDay(for: d)
                            withAnimation(.snappy(duration: 0.2)) {
                                selectedDay = (selectedDay == day) ? nil : day
                            }
                        }
                }
            }
            .chartForegroundStyleScale(
                domain: providers.map(\.displayName),
                range: providers.map(color)
            )
            .chartYAxis {
                AxisMarks(position: .leading) { v in
                    AxisGridLine().foregroundStyle(.primary.opacity(0.06))
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

    // MARK: day drill-down

    private var dayBanner: some View {
        let ev = dayEvents
        let total = ev.reduce(0) { $0 + $1.total }
        let cost = ev.reduce(0.0) { $0 + Pricing.cost($1) }
        return HStack(spacing: 12) {
            Image(systemName: "calendar").foregroundStyle(.secondary)
            Text(dayLabel).font(.system(size: 13, weight: .semibold))
            Text(total.compact).font(.system(size: 13, design: .monospaced))
            Text("tokens").font(.system(size: 11)).foregroundStyle(.tertiary)
            Text("≈ \(cost.usd)").font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
            Text("· \(ev.count) calls").font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
            ForEach(providers) { p in
                let t = ev.filter { $0.provider == p }.reduce(0) { $0 + $1.total }
                if t > 0 {
                    HStack(spacing: 4) {
                        Circle().fill(color(p)).frame(width: 7, height: 7)
                        Text(t.compact).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Button {
                withAnimation(.snappy(duration: 0.2)) { selectedDay = nil }
            } label: {
                Label("Back to \(store.window.rawValue)", systemImage: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quaternary))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .glassCard(radius: 10)
    }

    /// Aggregate the selected day's events by a key path (project / model / source).
    private func dayRows(_ key: KeyPath<UsageEvent, String>) -> [Row] {
        var acc: [String: (TokenBreakdown, Set<Provider>)] = [:]
        for e in dayEvents {
            var cur = acc[e[keyPath: key]] ?? (TokenBreakdown(), [])
            cur.0.add(e, cost: Pricing.cost(e)); cur.1.insert(e.provider)
            acc[e[keyPath: key]] = cur
        }
        return acc.map { Row(id: $0.key, name: $0.key, stats: $0.value.0, provider: $0.value.1.count == 1 ? $0.value.1.first : nil) }
            .sorted { $0.stats.total > $1.stats.total }
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
                                else { Circle().fill(.primary.opacity(0.3)).frame(width: 7, height: 7) }
                                Text(r.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(r.stats.total.compact).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary)
                                Text(r.stats.cost.usd).font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(r.provider.map(color) ?? .primary.opacity(0.7)).frame(width: 60, alignment: .trailing)
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
                            stat("Cache read", b.cacheRead, .primary.opacity(0.3))
                            stat("Cache write", b.cacheWrite, .primary.opacity(0.5))
                        }
                        if let l = store.limits[p], !l.limits.isEmpty {
                            Divider().opacity(0.3)
                            ForEach(l.limits) { lim in
                                HStack {
                                    Text(lim.name).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                                    GeometryReader { g in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(.primary.opacity(0.08))
                                            Capsule().fill(color(p)).frame(width: max(3, g.size.width * CGFloat(min(lim.percent, 100)) / 100))
                                        }
                                    }.frame(height: 6)
                                    Text("\(Int(lim.percent))%").font(.system(size: 11, weight: .bold, design: .rounded)).frame(width: 36, alignment: .trailing)
                                    Text(lim.resetText).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                                        .frame(width: 130, alignment: .trailing).lineLimit(1).minimumScaleFactor(0.75)
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
            .glassCard(radius: 14)
    }
}
