import SwiftUI

/// Draws the pose on top of the camera preview.
/// Left side of the body is blue, right side orange, center white, so a raised
/// left arm should light up blue. Faded joints are low confidence (0.3-0.5).
struct SkeletonOverlay: View {
    let frame: PoseFrame

    var body: some View {
        Canvas { context, size in
            let transform = AspectFillTransform(imageSize: frame.imageSize, viewSize: size)
            func point(_ name: JointName) -> CGPoint? {
                frame[name].map { transform.viewPoint(fromNormalized: $0.position) }
            }

            for (a, b) in PoseFrame.bones {
                guard let p1 = point(a), let p2 = point(b) else { continue }
                var path = Path()
                path.move(to: p1)
                path.addLine(to: p2)
                let side = a.side == .center ? b.side : a.side
                context.stroke(path, with: .color(Self.color(for: side).opacity(0.85)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }

            for (name, joint) in frame.joints {
                guard let p = point(name) else { continue }
                let radius: CGFloat = 6
                let rect = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
                let opacity = joint.confidence >= 0.5 ? 1.0 : 0.45
                context.fill(Path(ellipseIn: rect), with: .color(Self.color(for: name.side).opacity(opacity)))
                context.stroke(Path(ellipseIn: rect), with: .color(.black.opacity(0.4)), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }

    static func color(for side: JointName.Side) -> Color {
        switch side {
        case .left: .blue
        case .right: .orange
        case .center: .white
        }
    }
}
