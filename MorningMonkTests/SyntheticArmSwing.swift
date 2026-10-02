import CoreGraphics
import Foundation
@testable import MorningMonk

/// Stick figure doing arm swings, seen from 45°, in a 720x1280 frame.
/// Torso (neck to mid-hip) is 320px, each arm segment 150px, each leg segment 170px.
/// Stand-in for real recordings until we have them.
struct SyntheticArmSwing {
    var swingsPerSecond = 0.8
    /// Peak arm angle from hanging straight down. 90 = shoulder height.
    var amplitudeDegrees = 80.0
    /// 0 = straight arms.
    var elbowBendDegrees = 0.0
    /// Knee bounce during every Nth swing. nil = never bounce.
    var bounceEverySwings: Int? = 5
    var bounceDepthPixels = 25.0
    var duration: TimeInterval = 20
    var fps = 30.0

    static let imageSize = CGSize(width: 720, height: 1280)

    func frames() -> [PoseFrame] {
        (0..<Int(duration * fps)).map { i in
            let t = Double(i) / fps
            let joints = positions(at: t).mapValues { p in
                Joint(position: CGPoint(x: p.x / Self.imageSize.width, y: p.y / Self.imageSize.height), confidence: 0.9)
            }
            return PoseFrame(timestamp: t, imageSize: Self.imageSize, joints: joints)
        }
    }

    private func positions(at t: Double) -> [JointName: CGPoint] {
        let cycle = swingsPerSecond * t
        let theta = amplitudeDegrees * sin(2 * .pi * cycle) * .pi / 180
        let bend = elbowBendDegrees * .pi / 180
        // Forward/back motion is foreshortened by cos(45°) from this camera angle.
        let foreshorten = 0.707

        var drop = 0.0
        if let every = bounceEverySwings, Int(cycle) % every == every - 1 {
            drop = bounceDepthPixels * sin(.pi * (cycle - cycle.rounded(.down)))
        }

        var joints: [JointName: CGPoint] = [
            .nose: CGPoint(x: 360, y: 340 + drop),
            .neck: CGPoint(x: 360, y: 400 + drop),
            .root: CGPoint(x: 360, y: 720 + drop),
        ]

        for side in [-1.0, 1.0] {
            let isLeft = side < 0
            let shoulderX = 360 + 60 * side, shoulderY = 400 + drop
            let elbowX = shoulderX + 150 * sin(theta) * foreshorten
            let elbowY = shoulderY + 150 * cos(theta)
            let wristX = elbowX + 150 * sin(theta + bend) * foreshorten
            let wristY = elbowY + 150 * cos(theta + bend)

            let hipX = 360 + 40 * side, hipY = 720 + drop
            let ankleY = 1060.0
            let halfReach = (ankleY - hipY) / 2
            let kneeForward = (170 * 170 - halfReach * halfReach).squareRoot()
            let kneeX = hipX + kneeForward * foreshorten

            joints[isLeft ? .leftShoulder : .rightShoulder] = CGPoint(x: shoulderX, y: shoulderY)
            joints[isLeft ? .leftElbow : .rightElbow] = CGPoint(x: elbowX, y: elbowY)
            joints[isLeft ? .leftWrist : .rightWrist] = CGPoint(x: wristX, y: wristY)
            joints[isLeft ? .leftHip : .rightHip] = CGPoint(x: hipX, y: hipY)
            joints[isLeft ? .leftKnee : .rightKnee] = CGPoint(x: kneeX, y: hipY + halfReach)
            joints[isLeft ? .leftAnkle : .rightAnkle] = CGPoint(x: hipX, y: ankleY)
        }
        return joints
    }
}

enum DetectorHarness {
    struct Result {
        var final: MoveDetectorOutput
        /// Every fault that was active at any point.
        var faultsSeen: Set<String>
        /// When each fault first became active.
        var firstActive: [String: TimeInterval]
    }

    static func run(_ frames: [PoseFrame], through detector: MoveDetector) -> Result {
        var result = Result(final: MoveDetectorOutput(), faultsSeen: [], firstActive: [:])
        for frame in frames {
            let output = detector.process(frame)
            for fault in output.activeFaults where result.firstActive[fault] == nil {
                result.firstActive[fault] = frame.timestamp
            }
            result.faultsSeen.formUnion(output.activeFaults)
            result.final = output
        }
        return result
    }
}
