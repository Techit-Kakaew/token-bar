import SwiftUI
import AppKit

/// AppKit vibrancy behind a SwiftUI hierarchy.
struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material; v.blendingMode = blending; v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material; v.blendingMode = blending }
}

/// Retunes the host window (MenuBarExtra panel / dashboard) toward a lighter, more translucent glass:
/// swaps the system NSVisualEffectView material and clears the window background.
struct WindowGlassTuner: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    func makeNSView(context: Context) -> NSView {
        let v = Tuner(); v.material = material; return v
    }
    func updateNSView(_ nsView: NSView, context: Context) { (nsView as? Tuner)?.apply() }

    final class Tuner: NSView {
        var material: NSVisualEffectView.Material = .hudWindow
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); apply() }
        func apply() {
            guard let window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            func walk(_ v: NSView) {
                if let e = v as? NSVisualEffectView { e.material = material; e.blendingMode = .behindWindow; e.state = .active }
                v.subviews.forEach(walk)
            }
            if let c = window.contentView?.superview { walk(c) } else if let c = window.contentView { walk(c) }
        }
    }
}

/// Card surface: Liquid Glass on macOS 26, thin material + hairline elsewhere. Snapshot mode uses a flat tint.
struct GlassCard: ViewModifier {
    var accent: Color? = nil
    var radius: CGFloat = 12
    var interactive = false
    @Environment(\.isSnapshot) private var isSnapshot

    func body(content: Content) -> some View {
        if isSnapshot {
            content.background(
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.primary.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(accent?.opacity(0.35) ?? Color(nsColor: .separatorColor), lineWidth: 1)))
        } else {
            liquid(content)
        }
    }

    @ViewBuilder
    private func liquid(_ content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            let base: Glass = interactive ? .regular.interactive() : .regular
            content
                .glassEffect(accent.map { base.tint($0.opacity(0.10)) } ?? base, in: shape)
                .overlay(shape.strokeBorder(accent?.opacity(0.28) ?? Color.clear, lineWidth: 1))
        } else {
            legacy(content)
        }
        #else
        legacy(content)
        #endif
    }

    private func legacy(_ content: Content) -> some View {
        content.background(
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.thinMaterial)
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(accent?.opacity(0.35) ?? Color(nsColor: .separatorColor), lineWidth: 1)
            })
    }
}

extension View {
    func glassCard(accent: Color? = nil, radius: CGFloat = 12, interactive: Bool = false) -> some View {
        modifier(GlassCard(accent: accent, radius: radius, interactive: interactive))
    }
}
