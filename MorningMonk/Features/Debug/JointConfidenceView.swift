import SwiftUI

/// Every joint's raw Vision confidence, including ones dropped by the 0.3 threshold.
struct JointConfidenceView: View {
    let confidences: [JointName: Float]
    let threshold: Float

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(JointName.allCases, id: \.self) { name in
                let confidence = confidences[name]
                HStack(spacing: 6) {
                    Circle()
                        .fill(SkeletonOverlay.color(for: name.side))
                        .frame(width: 6, height: 6)
                    Text(name.rawValue)
                        .frame(width: 96, alignment: .leading)
                    bar(confidence ?? 0)
                    Text(confidence.map { String(format: "%.2f", $0) } ?? "  -  ")
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.white)
        .padding(10)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }

    private func bar(_ value: Float) -> some View {
        let color: Color = value >= 0.5 ? .green : value >= threshold ? .yellow : .red
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule().fill(color).frame(width: geo.size.width * CGFloat(min(max(value, 0), 1)))
            }
        }
        .frame(width: 70, height: 6)
    }
}
