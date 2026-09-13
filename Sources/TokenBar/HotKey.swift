import AppKit
import Carbon.HIToolbox

/// Global hotkeys via Carbon (no Accessibility permission needed).
@MainActor
final class HotKeys {
    struct Combo: Hashable {
        let key: UInt32; let mods: UInt32; let label: String
        static let off = Combo(key: 0, mods: 0, label: "Off")
        static let presets: [Combo] = [
            .off,
            Combo(key: UInt32(kVK_ANSI_T), mods: UInt32(optionKey | shiftKey), label: "⌥⇧T"),
            Combo(key: UInt32(kVK_ANSI_T), mods: UInt32(controlKey | optionKey), label: "⌃⌥T"),
            Combo(key: UInt32(kVK_ANSI_T), mods: UInt32(cmdKey | shiftKey), label: "⌘⇧T"),
            Combo(key: UInt32(kVK_Space), mods: UInt32(optionKey | shiftKey), label: "⌥⇧Space"),
        ]
        static func named(_ l: String) -> Combo { presets.first { $0.label == l } ?? .off }
    }

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: () -> Void] = [:]
    private var handler: EventHandlerRef?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let me = Unmanaged<HotKeys>.fromOpaque(userData!).takeUnretainedValue()
            Task { @MainActor in me.actions[id.id]?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func bind(id: UInt32, combo: Combo, action: @escaping () -> Void) {
        if let r = refs[id] { UnregisterEventHotKey(r); refs[id] = nil }
        actions[id] = nil
        guard combo != .off else { return }
        var ref: EventHotKeyRef?
        let hk = EventHotKeyID(signature: OSType(0x54_4B_42_52 /* TKBR */), id: id)
        if RegisterEventHotKey(combo.key, combo.mods, hk, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
            refs[id] = ref; actions[id] = action
        }
    }

    /// Simulate a click on our status-bar button to toggle the MenuBarExtra popover.
    static func toggleStatusItem() {
        for w in NSApp.windows where w.className.contains("NSStatusBarWindow") {
            if let button = w.contentView?.firstSubview(of: NSStatusBarButton.self) {
                button.performClick(nil); return
            }
        }
    }
}

private extension NSView {
    func firstSubview<T: NSView>(of type: T.Type) -> T? {
        if let v = self as? T { return v }
        for s in subviews { if let f = s.firstSubview(of: type) { return f } }
        return nil
    }
}
