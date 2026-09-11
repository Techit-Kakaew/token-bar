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
