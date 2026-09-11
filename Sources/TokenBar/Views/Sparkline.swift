import SwiftUI

struct Sparkline: View {
    let values: [Int]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let maxV = max(values.max() ?? 1, 1)
            let w = geo.size.width / CGFloat(values.count)
            HStack(alignment: .bottom, spacing: w * 0.35) {
                ForEach(values.indices, id: \.self) { i in
                    let h = max(2, geo.size.height * CGFloat(values[i]) / CGFloat(maxV))
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(i == values.count - 1 ? color : color.opacity(0.45))
                        .frame(height: h)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

/// AppKit vibrancy behind a SwiftUI hierarchy (macOS-native glass).
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

/// Native-looking card: thin material + hairline separator, optional accent tint on the border.
struct GlassCard: ViewModifier {
    var accent: Color? = nil
    var radius: CGFloat = 12
    @Environment(\.isSnapshot) private var isSnapshot
    func body(content: Content) -> some View {
        content.background(
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(isSnapshot ? AnyShapeStyle(.primary.opacity(0.05)) : AnyShapeStyle(.thinMaterial))
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(accent?.opacity(0.35) ?? Color(nsColor: .separatorColor), lineWidth: 1)
            }
        )
    }
}
extension View {
    func glassCard(accent: Color? = nil, radius: CGFloat = 12) -> some View { modifier(GlassCard(accent: accent, radius: radius)) }
}
