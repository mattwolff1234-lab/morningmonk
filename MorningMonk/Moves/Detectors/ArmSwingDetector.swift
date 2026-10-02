import Foundation

/// Shuai Shou Gong arm swings, viewed at ~45°.
///
/// All positions are in torso lengths (neck to mid-hip), which stays stable when the
/// user turns, unlike shoulder width. y grows downward: a wrist at shoulder height is 0,
/// hanging arms are about +1.
final class ArmSwingDetector: MoveDetector {
    static let moveID = "arm_swings"

    enum Fault {
        static let armsTooHigh = "arms_too_high"
        static let bentElbows = "bent_elbows"
        static let noBounce = "no_bounce"
    }

    static let requiredThresholds = [
        "faultPersistSeconds", "faultClearSeconds", "scoreFloor",
        "swingHysteresis", "activeWindowSeconds",
        "armsTooHighMargin", "peakWindowSeconds",
        "minElbowAngle", "elbowWindowSeconds",
        "maxSwingsWithoutDip", "kneeDipDegrees", "hipDipTorso", "baselineWindowSeconds",
    ]

    private struct State {
        var swings: OscillationCounter
        var countedSwings = 0
        var wristPeaks: RollingWindow
        var elbowAngles: RollingWindow
        var kneeAngles: RollingWindow
        var hipHeights: RollingWindow
        var swingsSinceDip = 0
        var dips = 0
        var inDip = false
        var faults: FaultTracker
        var score: ScoreAccumulator
        var output = MoveDetectorOutput()

        init(_ definition: MoveDefinition) {
            let t = definition.thresholds
            swings = OscillationCounter(hysteresis: t["swingHysteresis"])
            wristPeaks = RollingWindow(duration: t["peakWindowSeconds"])
            elbowAngles = RollingWindow(duration: t["elbowWindowSeconds"])
            kneeAngles = RollingWindow(duration: t["baselineWindowSeconds"])
            hipHeights = RollingWindow(duration: t["baselineWindowSeconds"])
            faults = FaultTracker(
                order: definition.faults.map(\.id),
                persistSeconds: t["faultPersistSeconds"],
                clearSeconds: t["faultClearSeconds"]
            )
            score = ScoreAccumulator(floor: t["scoreFloor"])
        }
    }

    let definition: MoveDefinition
    private let t: Thresholds
    private var s: State

    init(definition: MoveDefinition) {
        self.definition = definition
        t = definition.thresholds
        s = State(definition)
    }

    func reset() {
        s = State(definition)
    }

    func process(_ frame: PoseFrame) -> MoveDetectorOutput {
        let now = frame.timestamp
        guard let scale = frame.torsoLength,
              frame[.leftShoulder] != nil, frame[.rightShoulder] != nil
        else { return untracked(at: now) }

        let wrists = [JointName.leftWrist, .rightWrist].compactMap { frame.normalizedPoint($0, scale: scale) }
        guard !wrists.isEmpty else { return untracked(at: now) }

        // Swings: wrists travel forward and back past the body, which reads as
        // horizontal motion from a 45° angle.
        let wristX = wrists.reduce(0.0) { $0 + Double($1.x) } / Double(wrists.count)
        s.swings.update(wristX, at: now)
        if s.swings.cycles > s.countedSwings {
            s.swingsSinceDip += s.swings.cycles - s.countedSwings
            s.countedSwings = s.swings.cycles
        }
        let isMoving = s.swings.lastTransitionTime.map { now - $0 <= t["activeWindowSeconds"] } ?? false

        // Highest wrist this frame (smallest y).
        let highestWrist = wrists.map { Double($0.y) }.min() ?? 0
        s.wristPeaks.add(highestWrist, at: now)

        let elbows = [
            frame.angle(at: .leftElbow, from: .leftShoulder, to: .leftWrist),
            frame.angle(at: .rightElbow, from: .rightShoulder, to: .rightWrist),
        ].compactMap { $0 }
        if !elbows.isEmpty {
            s.elbowAngles.add(elbows.reduce(0, +) / Double(elbows.count), at: now)
        }

        let kneeAngle = detectDip(frame, scale: scale, at: now)

        let peak = s.wristPeaks.min ?? 0
        let elbowAverage = s.elbowAngles.mean
        let conditions: [String: Bool] = [
            Fault.armsTooHigh: isMoving && peak < -t["armsTooHighMargin"],
            Fault.bentElbows: isMoving && (elbowAverage ?? 180) < t["minElbowAngle"],
            Fault.noBounce: isMoving && Double(s.swingsSinceDip) >= t["maxSwingsWithoutDip"],
        ]
        s.faults.update(conditions, at: now)
        s.score.add(at: now, isMoving: isMoving, isClean: s.faults.active.isEmpty)

        s.output = MoveDetectorOutput(
            reps: s.swings.cycles,
            formScore: s.score.score,
            isTracking: true,
            isMoving: isMoving,
            activeFaults: s.faults.active,
            faultConditions: conditions,
            metrics: [
                DebugMetric(name: "swings/min", value: s.swings.cyclesPerMinute(at: now).map { String(format: "%.0f", $0) } ?? "-"),
                DebugMetric(name: "wrist peak (torso)", value: String(format: "%+.2f", peak)),
                DebugMetric(name: "elbow avg °", value: elbowAverage.map { String(format: "%.0f", $0) } ?? "-"),
                DebugMetric(name: "knee °", value: kneeAngle.map { String(format: "%.0f", $0) } ?? "-"),
                DebugMetric(name: "swings since dip", value: "\(s.swingsSinceDip)"),
                DebugMetric(name: "dips", value: "\(s.dips)"),
            ]
        )
        return s.output
    }

    /// Knee bounce: knees bend noticeably below their recent straightest, or the hips
    /// drop below their recent highest. Returns the current knee angle for display.
    private func detectDip(_ frame: PoseFrame, scale: CGFloat, at now: TimeInterval) -> Double? {
        var dipping = false

        let knees = [
            frame.angle(at: .leftKnee, from: .leftHip, to: .leftAnkle),
            frame.angle(at: .rightKnee, from: .rightHip, to: .rightAnkle),
        ].compactMap { $0 }
        let kneeAngle = knees.isEmpty ? nil : knees.reduce(0, +) / Double(knees.count)
        if let kneeAngle {
            s.kneeAngles.add(kneeAngle, at: now)
            if let straightest = s.kneeAngles.max, kneeAngle < straightest - t["kneeDipDegrees"] {
                dipping = true
            }
        }

        // Absolute hip height in the image: the whole upper body drops on a bounce,
        // so this can't be measured relative to the shoulders.
        if let root = frame.pixelPoint(.root) {
            let hipY = Double(root.y / scale)
            s.hipHeights.add(hipY, at: now)
            if let highest = s.hipHeights.min, hipY > highest + t["hipDipTorso"] {
                dipping = true
            }
        }

        if dipping && !s.inDip {
            s.dips += 1
            s.swingsSinceDip = 0
        }
        s.inDip = dipping
        return kneeAngle
    }

    private func untracked(at now: TimeInterval) -> MoveDetectorOutput {
        s.score.skip(at: now)
        s.output.isTracking = false
        s.output.isMoving = false
        return s.output
    }
}
