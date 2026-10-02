import CoreGraphics
import Foundation

/// The 19 joints reported by `VNDetectHumanBodyPoseRequest`.
///
/// Names are anatomical: `leftWrist` is the user's actual left wrist, regardless of
/// the mirrored display.
enum JointName: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable {
    case nose, leftEye, rightEye, leftEar, rightEar
    case neck
    case leftShoulder, rightShoulder
    case leftElbow, rightElbow
    case leftWrist, rightWrist
    case root
    case leftHip, rightHip
    case leftKnee, rightKnee
    case leftAnkle, rightAnkle

    enum Side { case left, right, center }

    var side: Side {
        let name = rawValue
        if name.hasPrefix("left") { return .left }
        if name.hasPrefix("right") { return .right }
        return .center
    }
}

struct Joint: Codable, Equatable, Sendable {
    /// Normalized display coordinates: (0, 0) top-left, (1, 1) bottom-right, mirrored
    /// so it matches what the user sees on screen (like a mirror).
    var position: CGPoint
    var confidence: Float
}

/// One processed camera frame. Joints below the confidence threshold are already removed.
struct PoseFrame: Codable, Equatable, Sendable {
    /// Seconds, from the capture clock. Monotonic within a session.
    var timestamp: TimeInterval
    /// Pixel size of the (rotated, upright) image the joints were detected in.
    var imageSize: CGSize
    var joints: [JointName: Joint]

    static let bones: [(JointName, JointName)] = [
        (.leftEar, .leftEye), (.leftEye, .nose), (.nose, .rightEye), (.rightEye, .rightEar),
        (.nose, .neck),
        (.neck, .leftShoulder), (.neck, .rightShoulder),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.neck, .root),
        (.root, .leftHip), (.root, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
    ]

    subscript(_ joint: JointName) -> Joint? { joints[joint] }

    /// Joint position in pixels, so x and y distances are directly comparable.
    func pixelPoint(_ joint: JointName) -> CGPoint? {
        guard let p = joints[joint]?.position else { return nil }
        return CGPoint(x: p.x * imageSize.width, y: p.y * imageSize.height)
    }

    /// Distance between the shoulders in pixels. The body-scale unit for thresholds.
    var shoulderWidth: CGFloat? {
        guard let l = pixelPoint(.leftShoulder), let r = pixelPoint(.rightShoulder) else { return nil }
        let width = hypot(l.x - r.x, l.y - r.y)
        return width > 0 ? width : nil
    }

    /// Joint position relative to the shoulder midpoint, in shoulder widths.
    /// y grows downward, matching screen coordinates.
    ///
    /// Pass `scale` to use a calibrated shoulder width instead of this frame's, which is
    /// required for side-on moves where projected shoulder width collapses.
    func normalizedPoint(_ joint: JointName, scale: CGFloat? = nil) -> CGPoint? {
        guard let point = pixelPoint(joint),
              let l = pixelPoint(.leftShoulder), let r = pixelPoint(.rightShoulder),
              let unit = scale ?? shoulderWidth, unit > 0
        else { return nil }
        let origin = CGPoint(x: (l.x + r.x) / 2, y: (l.y + r.y) / 2)
        return CGPoint(x: (point.x - origin.x) / unit, y: (point.y - origin.y) / unit)
    }

    /// Interior angle at `vertex` in degrees (0-180), e.g. elbow angle is
    /// `angle(at: .leftElbow, from: .leftShoulder, to: .leftWrist)`.
    func angle(at vertex: JointName, from a: JointName, to c: JointName) -> Double? {
        guard let b = pixelPoint(vertex), let pa = pixelPoint(a), let pc = pixelPoint(c) else { return nil }
        let v1 = CGVector(dx: pa.x - b.x, dy: pa.y - b.y)
        let v2 = CGVector(dx: pc.x - b.x, dy: pc.y - b.y)
        let m1 = hypot(v1.dx, v1.dy), m2 = hypot(v2.dx, v2.dy)
        guard m1 > 0, m2 > 0 else { return nil }
        let cosine = max(-1, min(1, (v1.dx * v2.dx + v1.dy * v2.dy) / (m1 * m2)))
        return acos(Double(cosine)) * 180 / .pi
    }

    /// True when every listed joint is present at or above `confidence`.
    func hasJoints(_ names: [JointName], confidence: Float) -> Bool {
        names.allSatisfy { (joints[$0]?.confidence ?? 0) >= confidence }
    }
}
