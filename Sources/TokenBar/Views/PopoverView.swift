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

    private var cards: some View {
        VStack(spacing: 8) {
            ForEach(Provider.allCases) { p in
                if let s = store.stats[p] {
                    ProviderCard(stats: s, window: store.window, limits: store.limits[p])
                }
            }
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
                Text("tokens")
                    .font(.system(size: 12)).foregroundStyle(.tertiary)
                Spacer()
                Text("≈ \(store.totalCost.usd)")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1).fixedSize()
            }
            streakRow
        }
        .padding(12)
    }

    @ViewBuilder
    private var streakRow: some View {
        if let s = store.breaks.streak {
            let mins = Int(s.duration / 60)
            let over = mins >= store.breaks.thresholdMinutes
            let dur = mins >= 60 ? "\(mins / 60)h \(mins % 60)m" : "\(mins)m"
            HStack(spacing: 6) {
                Image(systemName: over ? "cup.and.saucer.fill" : "flame.fill")
                    .font(.system(size: 10))
                Text(over ? "ใช้ต่อเนื่อง \(dur) — พักหน่อยไหม" : "streak \(dur)")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
            }
            .foregroundStyle(over ? Color(red: 1.0, green: 0.72, blue: 0.3) : .secondary)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .glassCard(accent: over ? Color(red: 1.0, green: 0.72, blue: 0.3) : nil, radius: 8)
        }
    }

    @ViewBuilder
    private var windowPicker: some View {
        if isSnapshot {
            HStack(spacing: 2) {
                ForEach(Window.allCases) { w in
                    Text(w.rawValue).font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 5).fill(w == store.window ? Color.primary.opacity(0.18) : Color.clear))
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 7).fill(.primary.opacity(0.06)))
        } else {
            Picker("", selection: $store.window) {
                ForEach(Window.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 170)
        }
    }

    private var settingsMenu: some View {
        Menu {
            Toggle("เปิดตอน Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
                    catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                }
            Toggle("แสดงตัวเลขบน menubar", isOn: Binding(get: { store.showNumberInBar }, set: { store.showNumberInBar = $0 }))
            Picker("แสดงบน menubar", selection: Binding(get: { store.menuBarProvider?.rawValue ?? "all" },
                                                         set: { store.menuBarProvider = Provider(rawValue: $0) })) {
                Text("รวมทุกเจ้า").tag("all")
                ForEach(Provider.allCases) { Text($0.displayName).tag($0.rawValue) }
            }
            Picker("ธีม", selection: Binding(get: { store.appearance }, set: { store.appearance = $0 })) {
                ForEach(UsageStore.Appearance.allCases) { Text($0.label).tag($0) }
            }
            Divider()
            Picker("เตือน limit เมื่อถึง", selection: Binding(get: { store.alerts.warnPercent }, set: { store.alerts.warnPercent = $0 })) {
                Text("ปิด (เฉพาะ 95%)").tag(0)
                ForEach([70, 80, 90], id: \.self) { Text("\($0)%  + 95%").tag($0) }
            }
            Divider()
            Toggle("เตือนให้พัก", isOn: Binding(get: { store.breaks.enabled }, set: { store.breaks.enabled = $0 }))
            Picker("เตือนหลังใช้ต่อเนื่อง", selection: Binding(get: { store.breaks.thresholdMinutes }, set: { store.breaks.thresholdMinutes = $0 })) {
                ForEach([45, 60, 90, 120, 180], id: \.self) { Text("\($0) นาที").tag($0) }
            }
            Picker("เตือนซ้ำทุก", selection: Binding(get: { store.breaks.repeatMinutes }, set: { store.breaks.repeatMinutes = $0 })) {
                ForEach([15, 30, 45, 60], id: \.self) { Text("\($0) นาที").tag($0) }
            }
            Picker("ถือว่าพักเมื่อเว้น", selection: Binding(get: { store.breaks.idleGapMinutes }, set: { store.breaks.idleGapMinutes = $0 })) {
                ForEach([10, 15, 20, 30], id: \.self) { Text("\($0) นาที").tag($0) }
            }
            if store.breaks.permissionDenied {
                Divider()
                Button("เปิดสิทธิ์ Notification…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                }
            }
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
                Label("Dashboard", systemImage: "rectangle.3.group")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .glassCard(radius: 7, interactive: true)
            }
            .buttonStyle(.plain)
            Spacer()
            if let t = store.lastRefresh {
                Text("updated \(t, style: .time)")
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
