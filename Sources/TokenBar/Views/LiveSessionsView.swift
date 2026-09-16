import SwiftUI

/// Live sessions. `compact` (popover): grouped by project, one line per row, top N + "more", collapsible.
/// Full (dashboard): every session with context gauge, model, calls, cost, duration.
struct LiveSessionsView: View {
    @EnvironmentObject var store: UsageStore
    let sessions: [LiveSession]
    var compact = true
    @State private var expandedGroups: Set<String> = []
    @State private var showAll = false

    private func color(_ p: Provider) -> Color { let (r, g, b) = p.accent; return Color(red: r, green: g, blue: b) }
    private func ctxColor(_ r: Double, _ base: Color) -> Color {
        r >= 0.9 ? Color(red: 1.0, green: 0.35, blue: 0.35) : (r >= 0.75 ? Color(red: 1.0, green: 0.72, blue: 0.3) : base)
    }
    private func dur(_ from: Date, _ to: Date) -> String {
        let m = Int(to.timeIntervalSince(from) / 60)
        return m >= 60 ? L("%dh %dm", m / 60, m % 60) : L("%dm", m)
    }
    private func name(_ s: LiveSession) -> String {
        store.liveShowTitles && !s.title.isEmpty ? s.title : "\(s.project) · \(s.shortId)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if !(compact && store.liveCollapsed) {
                if compact { compactList } else { fullList }
            }
        }
        .padding(12)
        .glassCard(accent: .green.opacity(0.6))
    }

    // MARK: header — summary + collapse chevron

    private var header: some View {
        let active = sessions.filter { $0.state == .active }.count
        let maxCtx = sessions.map(\.contextRatio).max() ?? 0
        return HStack(spacing: 6) {
            Circle().fill(active > 0 ? .green : .gray).frame(width: 6, height: 6)
            Text(L("LIVE SESSIONS")).font(.system(size: 9.5, weight: .bold)).tracking(1).foregroundStyle(.secondary)
            Text("\(sessions.count)").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
            if compact, store.liveCollapsed || sessions.count > 1 {
                if active > 0 { Text("· \(L("%d active", active))").font(.system(size: 10)).foregroundStyle(.tertiary) }
                if maxCtx > 0 {
                    Text("· ctx \(Int(maxCtx * 100))%").font(.system(size: 10, weight: .semibold)).foregroundStyle(ctxColor(maxCtx, .secondary))
                }
            }
            Spacer()
            if compact {
                Button { withAnimation(.snappy(duration: 0.2)) { store.liveCollapsed.toggle() } } label: {
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(store.liveCollapsed ? 0 : 90))
                }.buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if compact { withAnimation(.snappy(duration: 0.2)) { store.liveCollapsed.toggle() } } }
    }

    // MARK: compact (popover)

    private var compactList: some View {
        let groups = store.liveGroups
        let limit = store.liveMaxRows
        let shown = (showAll || limit == 0) ? groups : Array(groups.prefix(limit))
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(shown) { g in
                if g.sessions.count == 1 {
                    sessionRow(g.sessions[0], indent: false)
                } else {
                    groupRow(g)
                    if expandedGroups.contains(g.id) {
                        ForEach(g.sessions) { sessionRow($0, indent: true) }
                    }
                }
            }
            if groups.count > shown.count || (showAll && limit > 0 && groups.count > limit) {
                Button { withAnimation(.snappy(duration: 0.2)) { showAll.toggle() } } label: {
                    Text(showAll ? L("Show less") : L("+%d more", groups.count - shown.count))
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .glassCard(radius: 6, interactive: true)
                }.buttonStyle(.plain).padding(.top, 2)
            }
        }
    }

    /// One project with several sessions: "▸ codex-project ×3 · 2 active · ctx 38% · $0.25"
    private func groupRow(_ g: LiveGroup) -> some View {
        let c = color(g.provider)
        let open = expandedGroups.contains(g.id)
        return Button {
            withAnimation(.snappy(duration: 0.2)) { if open { expandedGroups.remove(g.id) } else { expandedGroups.insert(g.id) } }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right").font(.system(size: 7, weight: .bold)).foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(open ? 90 : 0)).frame(width: 8)
                ProviderLogoView(provider: g.provider, size: 10).foregroundStyle(c).frame(width: 14)
                Text(g.project).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text("×\(g.sessions.count)").font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 5).padding(.vertical, 1).background(Capsule().fill(c.opacity(0.2))).foregroundStyle(c)
                if g.activeCount > 0 {
                    Circle().fill(.green).frame(width: 5, height: 5)
                    Text("\(g.activeCount)").font(.system(size: 10)).foregroundStyle(.green)
                }
                Spacer(minLength: 6)
                Text("ctx \(Int(g.maxContext * 100))%").font(.system(size: 10.5, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(ctxColor(g.maxContext, c))
                Text(g.cost.usd).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                Text(g.last.agoTiny).font(.system(size: 9.5, design: .monospaced)).foregroundStyle(.tertiary).frame(width: 28, alignment: .trailing)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// One session on one line: "● title · source   ▓▓░ 62%  $7.97  1m"
    private func sessionRow(_ s: LiveSession, indent: Bool) -> some View {
        let c = color(s.provider)
        return HStack(spacing: 6) {
            if indent { Spacer().frame(width: 14) }
            Circle().fill(s.state == .active ? .green : .gray.opacity(0.6)).frame(width: 6, height: 6)
            if !indent { ProviderLogoView(provider: s.provider, size: 10).foregroundStyle(c).frame(width: 14) }
            VStack(alignment: .leading, spacing: 0) {
                Text(name(s)).font(.system(size: indent ? 11 : 12, weight: indent ? .regular : .semibold)).lineLimit(1).truncationMode(.tail)
                    .help("\(s.title.isEmpty ? s.project : s.title)\n\(s.model) · \(s.source) · \(L("%d calls · %@ · %@", s.calls, s.cost.usd, dur(s.started, s.last)))")
                Text((indent ? "" : "\(s.source) · ") + s.cost.usd + (s.subagentCalls > 0 ? " · ⑂\(s.subagentCalls)" : ""))
                    .font(.system(size: 9.5)).foregroundStyle(.tertiary).lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 6)
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.08))
                Capsule().fill(ctxColor(s.contextRatio, c)).frame(width: max(3, 44 * CGFloat(min(s.contextRatio, 1))))
            }.frame(width: 44, height: 5)
            Text("\(Int((s.contextRatio * 100).rounded()))%").font(.system(size: 10.5, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(ctxColor(s.contextRatio, c)).frame(width: 34, alignment: .trailing)
            Text(s.last.agoTiny).font(.system(size: 9.5, design: .monospaced)).foregroundStyle(.tertiary).frame(width: 28, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    // MARK: full (dashboard)

    private var fullList: some View {
        ForEach(sessions) { s in
            let c = color(s.provider)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    ProviderLogoView(provider: s.provider, size: 10).foregroundStyle(c).frame(width: 14)
                    Text(s.project).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text("· \(s.source)").font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                    if store.liveShowTitles, !s.title.isEmpty {
                        Text("— \(s.title)").font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                    }
                    Spacer()
                    Circle().fill(s.state == .active ? .green : .gray).frame(width: 6, height: 6)
                    Text(s.state == .active ? L("active") : L("idle")).font(.system(size: 10)).foregroundStyle(s.state == .active ? .green : .secondary)
                    Text(s.last.agoShort).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                }
                HStack(spacing: 8) {
                    Text(L("context")).font(.system(size: 9.5)).foregroundStyle(.tertiary).frame(width: 44, alignment: .leading)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.primary.opacity(0.08))
                            Capsule().fill(ctxColor(s.contextRatio, c)).frame(width: max(3, g.size.width * CGFloat(min(s.contextRatio, 1))))
                        }
                    }.frame(height: 6)
                    Text("\(Int((s.contextRatio * 100).rounded()))%").font(.system(size: 11, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(ctxColor(s.contextRatio, c)).frame(width: 36, alignment: .trailing)
                    Text("\(s.contextTokens.compact) / \(s.contextWindow.compact)").font(.system(size: 9.5, design: .monospaced)).foregroundStyle(.tertiary)
                        .frame(width: 92, alignment: .trailing).lineLimit(1).minimumScaleFactor(0.8)
                }
                HStack {
                    Text(s.model + (s.subagentCalls > 0 ? "  ⑂ \(L("%d subagent calls", s.subagentCalls))" : ""))
                        .font(.system(size: 9.5, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1)
                    Spacer()
                    Text(L("%d calls · %@ · %@", s.calls, s.cost.usd, dur(s.started, s.last))).font(.system(size: 9.5, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
            if s.id != sessions.last?.id { Divider().opacity(0.3) }
        }
    }
}
