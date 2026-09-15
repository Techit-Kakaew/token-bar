import SwiftUI
import ServiceManagement

private struct HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct SnapshotKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// True when rendering headless via ImageRenderer (AppKit-backed controls are swapped for plain views).
    var isSnapshot: Bool { get { self[SnapshotKey.self] } set { self[SnapshotKey.self] = newValue } }
}

struct PopoverView: View {
    @EnvironmentObject var store: UsageStore
    @Environment(\.isSnapshot) private var isSnapshot
    @Environment(\.openWindow) private var openWindow
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(spacing: 0) {
            topBar
            scrollableCards
            footer
        }
        .frame(width: 380)
        .id(store.language)   // force full re-render (incl. cards) when the language changes
        .environment(\.locale, L10n.current.locale)
        .background { if !isSnapshot { WindowGlassTuner(material: .hudWindow) } }
    }

    @State private var cardsHeight: CGFloat = 0

    /// ScrollView has no intrinsic height inside MenuBarExtra, so measure the content and cap at screen height.
    @ViewBuilder
    private var scrollableCards: some View {
        if isSnapshot {
            cards
        } else {
            let maxH = (NSScreen.main?.visibleFrame.height ?? 900) - 180
            ScrollView(.vertical, showsIndicators: false) {
                cards.background(GeometryReader { g in
                    Color.clear.preference(key: HeightKey.self, value: g.size.height)
                })
            }
            .onPreferenceChange(HeightKey.self) { cardsHeight = $0 }
            .frame(height: min(max(cardsHeight, 100), maxH))
        }
    }

    private var visibleProviders: [Provider] { store.visibleProviders }

    /// "Hidden: [Codex CLI ×] [Gemini ×]" — click a chip to bring the card back.
    private var hiddenChips: some View {
        HStack(spacing: 6) {
            Image(systemName: "eye.slash").font(.system(size: 9)).foregroundStyle(.tertiary)
            Text(L("Hidden")).font(.system(size: 10)).foregroundStyle(.tertiary)
            ForEach(store.hiddenButAvailable) { p in
                Button { withAnimation(.snappy(duration: 0.25)) { store.setHidden(p, false) } } label: {
                    HStack(spacing: 4) {
                        ProviderLogoView(provider: p, size: 8).foregroundStyle(.secondary)
                        Text(p.displayName).font(.system(size: 10, weight: .medium))
                        Image(systemName: "plus.circle.fill").font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .glassCard(radius: 7, interactive: true)
                }
                .buttonStyle(.plain)
                .help(L("Show %@", p.displayName))
            }
            Spacer()
        }
        .padding(.horizontal, 4).padding(.top, 2)
    }

    private var onboardingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(nsImage: MenuBarIcon.image).renderingMode(.template)
                Text(L("onb.title")).font(.system(size: 13, weight: .semibold))
            }
            Text(L("onb.body")).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button {
                    store.claudeLimitsEnabled = true
                    store.breaks.requestPermission()
                    withAnimation { store.onboarded = true }
                } label: {
                    Text("\(L("onb.enableLimits")) + \(L("onb.enableNotifs"))").font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                Button(L("onb.skip")) { withAnimation { store.onboarded = true } }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(12)
        .glassCard(accent: Color(red: 0.55, green: 0.65, blue: 1.0))
    }

    private var cards: some View {
        VStack(spacing: 8) {
            if !store.onboarded { onboardingCard }
            if !store.visibleLiveSessions.isEmpty { LiveSessionsView(sessions: store.visibleLiveSessions) }
            if visibleProviders.isEmpty {
                let anyData = Provider.allCases.contains { store.stats[$0]?.available == true }
                VStack(alignment: .leading, spacing: 6) {
                    Text(L(anyData ? "nodata.window" : "No local data found")).font(.system(size: 13, weight: .semibold))
                    if !anyData { Text(L("nodata.hint")).font(.system(size: 11)).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .glassCard()
            }
            ForEach(visibleProviders) { p in
                if let s = store.stats[p] {
                    ProviderCard(stats: s, window: store.window, limits: store.limits[p],
                                 onHide: { withAnimation(.snappy(duration: 0.25)) { store.setHidden(p, true) } })
                        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.98)), removal: .opacity.combined(with: .scale(scale: 0.96))))
                }
            }
            if !store.hiddenButAvailable.isEmpty { hiddenChips }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("TOKENBAR").font(.system(size: 10, weight: .heavy)).tracking(2).foregroundStyle(.secondary)
                Spacer()
                windowPicker
            }
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(store.totalTokens.compact)
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .lineLimit(1).fixedSize()
                    .contentTransition(.numericText())
                Text(L("tokens"))
                    .font(.system(size: 12)).foregroundStyle(.tertiary)
                Spacer()
                Text("≈ \(store.totalCost.usd)")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1).fixedSize()
            }
            streakRow
            budgetRows
        }
        .padding(12)
        .onAppear { store.openDashboard = { openWindow(id: "dashboard") } }
    }

    @ViewBuilder
    private var budgetRows: some View {
        if let t = store.budget.today { budgetRow(L("day"), t) }
        if let w = store.budget.week { budgetRow(L("week"), w) }
    }

    private func budgetRow(_ label: String, _ s: Budget.Status) -> some View {
        let color: Color = s.ratio >= 1 ? Color(red: 1.0, green: 0.35, blue: 0.35)
            : (s.ratio >= 0.8 ? Color(red: 1.0, green: 0.72, blue: 0.3) : Color(red: 0.55, green: 0.65, blue: 1.0))
        return HStack(spacing: 8) {
            Image(systemName: "banknote").font(.system(size: 10)).foregroundStyle(color)
            Text(label).font(.system(size: 11, weight: .medium)).frame(width: 70, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.08))
                    Capsule().fill(color).frame(width: max(3, g.size.width * CGFloat(min(s.ratio, 1))))
                }
            }.frame(height: 6)
            Text(L("budget.row %@ %@", s.spent.usd, s.limit.usd))
                .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
            Text("\(Int((s.ratio * 100).rounded()))%")
                .font(.system(size: 11, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(color)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .glassCard(accent: s.ratio >= 0.8 ? color : nil, radius: 8)
    }

    @ViewBuilder
    private var streakRow: some View {
        let debugMins = ProcessInfo.processInfo.environment["TOKENBAR_SNAPSHOT_STREAK_MIN"].flatMap(Int.init)
        if let s = store.breaks.streak ?? debugMins.map({ BreakReminder.Streak(start: Date().addingTimeInterval(-Double($0) * 60), last: Date()) }) {
            let mins = debugMins ?? Int(s.duration / 60)
            let over = mins >= store.breaks.thresholdMinutes
            let dur = mins >= 60 ? L("%dh %dm", mins / 60, mins % 60) : L("%dm", mins)
            let level = Double(mins) / Double(max(store.breaks.thresholdMinutes, 1))
            HStack(spacing: 8) {
                FlameBadge(level: level, size: 18) {
                    Image(systemName: over ? "cup.and.saucer.fill" : "flame.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(level >= 0.25 ? .white : .secondary)
                }
                .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(over ? L("streak over %@", dur) : L("streak %@", dur))
                        .font(.system(size: 11, weight: .medium))
                    // stage bar: fills toward the break threshold
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.primary.opacity(0.08))
                            Capsule().fill(LinearGradient(colors: [Color(red: 1, green: 0.8, blue: 0.3), Color(red: 1, green: 0.35, blue: 0.25)],
                                                          startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(2, g.size.width * CGFloat(min(level, 1))))
                        }
                    }.frame(height: 3)
                }
                Text("\(Int((min(level, 1) * 100).rounded()))%")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(level >= 1 ? Color(red: 1.0, green: 0.35, blue: 0.25) : (level >= 0.5 ? Color(red: 1.0, green: 0.6, blue: 0.2) : .secondary))
            }
            .foregroundStyle(over ? Color(red: 1.0, green: 0.72, blue: 0.3) : .secondary)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .glassCard(accent: level >= 0.5 ? Color(red: 1.0, green: 0.55, blue: 0.2).opacity(min(level, 1)) : nil, radius: 8)
        }
    }

    @ViewBuilder
    private var windowPicker: some View {
        if isSnapshot {
            HStack(spacing: 2) {
                ForEach(Window.allCases) { w in
                    Text(w.label).font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 5).fill(w == store.window ? Color.primary.opacity(0.18) : Color.clear))
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 7).fill(.primary.opacity(0.06)))
        } else {
            Picker("", selection: $store.window) {
                ForEach(Window.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 190)
        }
    }

    private var settingsMenu: some View {
        Menu {
            Toggle(L("Launch at login"), isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
                    catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                }
            Toggle(L("Show number in menu bar"), isOn: Binding(get: { store.showNumberInBar }, set: { store.showNumberInBar = $0 }))
            Toggle(L("Claude limits (Keychain)"), isOn: Binding(get: { store.claudeLimitsEnabled }, set: { store.claudeLimitsEnabled = $0 }))
            Menu(L("Hidden providers")) {
                ForEach(store.availableProviders) { p in
                    Toggle(p.displayName, isOn: Binding(get: { store.hiddenProviders.contains(p) }, set: { store.setHidden(p, $0) }))
                }
            }
            Picker(L("Menu bar shows"), selection: Binding(get: { store.menuBarMode.isEmpty ? "all" : store.menuBarMode },
                                                         set: { store.menuBarMode = $0 == "all" ? "" : $0 })) {
                Text(L("All providers")).tag("all")
                Text(L("Follow live session")).tag("auto")
                Divider()
                ForEach(visibleProviders) { Text($0.displayName).tag($0.rawValue) }
            }
            Picker(L("Theme"), selection: Binding(get: { store.appearance }, set: { store.appearance = $0 })) {
                ForEach(UsageStore.Appearance.allCases) { Text($0.label).tag($0) }
            }
            Picker(L("Language"), selection: Binding(get: { store.language }, set: { store.language = $0 })) {
                Text(L("System")).tag("system")
                Text("ไทย").tag("th")
                Text("English").tag("en")
            }
            Divider()
            Picker(L("Daily budget"), selection: Binding(get: { store.budget.daily }, set: { store.budget.daily = $0 })) {
                ForEach(Budget.presets, id: \.self) { Text($0 == 0 ? L("Off") : $0.usd).tag($0) }
            }
            Picker(L("Weekly budget"), selection: Binding(get: { store.budget.weekly }, set: { store.budget.weekly = $0 })) {
                ForEach(Budget.presets, id: \.self) { Text($0 == 0 ? L("Off") : $0.usd).tag($0) }
            }
            Divider()
            Picker(L("Hotkey: popover"), selection: Binding(get: { store.hotkeyPopover }, set: { store.hotkeyPopover = $0 })) {
                ForEach(HotKeys.Combo.presets, id: \.label) { Text($0.label == "Off" ? L("Off") : $0.label).tag($0.label) }
            }
            Picker(L("Hotkey: dashboard"), selection: Binding(get: { store.hotkeyDashboard }, set: { store.hotkeyDashboard = $0 })) {
                ForEach(HotKeys.Combo.presets, id: \.label) { Text($0.label == "Off" ? L("Off") : $0.label).tag($0.label) }
            }
            Divider()
            Picker(L("Limit alert at"), selection: Binding(get: { store.alerts.warnPercent }, set: { store.alerts.warnPercent = $0 })) {
                Text(L("Off (95% only)")).tag(0)
                ForEach([70, 80, 90], id: \.self) { Text(L("%d%% + 95%%", $0)).tag($0) }
            }
            Divider()
            Toggle(L("Break reminder"), isOn: Binding(get: { store.breaks.enabled }, set: { store.breaks.enabled = $0 }))
            Picker(L("Remind after"), selection: Binding(get: { store.breaks.thresholdMinutes }, set: { store.breaks.thresholdMinutes = $0 })) {
                ForEach([45, 60, 90, 120, 180], id: \.self) { Text(L("%d min", $0)).tag($0) }
            }
            Picker(L("Repeat every"), selection: Binding(get: { store.breaks.repeatMinutes }, set: { store.breaks.repeatMinutes = $0 })) {
                ForEach([15, 30, 45, 60], id: \.self) { Text(L("%d min", $0)).tag($0) }
            }
            Picker(L("Idle gap = break"), selection: Binding(get: { store.breaks.idleGapMinutes }, set: { store.breaks.idleGapMinutes = $0 })) {
                ForEach([10, 15, 20, 30], id: \.self) { Text(L("%d min", $0)).tag($0) }
            }
            if store.breaks.permissionDenied {
                Divider()
                Button(L("Open Notification settings…")) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                }
            }
            Divider()
            Button(L("Check for updates…")) { Task { await store.updates.check(manual: true) } }
            Text("TokenBar \(store.updates.current)")
        } label: {
            Image(systemName: "gearshape").font(.system(size: 12))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .frame(width: 20)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                openWindow(id: "dashboard")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label(L("Dashboard"), systemImage: "rectangle.3.group")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .glassCard(radius: 7, interactive: true)
            }
            .buttonStyle(.plain)
            Spacer()
            if let v = store.updates.latest {
                Button {
                    if let u = store.updates.latestURL { NSWorkspace.shared.open(u) }
                } label: {
                    Label(L("update.badge %@", v), systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color(red: 0.55, green: 0.65, blue: 1.0))
                }
                .buttonStyle(.plain)
            }
            if let t = store.lastRefresh {
                Text(L("updated %@", t.formatted(date: .omitted, time: .shortened)))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                    .lineLimit(1).fixedSize()
            }
            Button { store.refreshClaudeLimits(force: true); store.refresh() } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
                    .animation(store.isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: store.isRefreshing)
            }
            .buttonStyle(.plain).font(.system(size: 12))
            if !isSnapshot { settingsMenu }
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .buttonStyle(.plain).font(.system(size: 12))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .overlay(alignment: .top) { Divider() }
    }
}
