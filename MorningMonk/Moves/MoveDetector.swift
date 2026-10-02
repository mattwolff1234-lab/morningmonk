import Foundation

struct DebugMetric: Identifiable, Equatable {
    let name: String
    let value: String
    var id: String { name }
}

struct MoveDetectorOutput: Equatable {
    var reps = 0
    var holdTime: TimeInterval = 0
    /// 0-100.
    var formScore: Double = 0
    /// False when the joints this move needs aren't visible.
    var isTracking = false
    /// True while the user is actually doing the move. Faults only fire while moving.
    var isMoving = false
    /// Faults that have persisted past `faultPersistSeconds`, in priority order.
    var activeFaults: [String] = []
    /// Raw per-frame fault conditions, before persistence. For debugging.
    var faultConditions: [String: Bool] = [:]
    var metrics: [DebugMetric] = []
}

/// Consumes pose frames for one move and reports reps, form score and faults.
protocol MoveDetector: AnyObject {
    var definition: MoveDefinition { get }
    func process(_ frame: PoseFrame) -> MoveDetectorOutput
    func reset()
}

enum DetectorFactory {
    static func make(for move: MoveDefinition) -> MoveDetector? {
        switch move.id {
        case ArmSwingDetector.moveID:
            return ArmSwingDetector(definition: move)
        default:
            return nil
        }
    }
}

/// A fault becomes active once its condition has held for `persistSeconds`, and
/// clears once the condition has been false for `clearSeconds`.
struct FaultTracker {
    let order: [String]
    let persistSeconds: TimeInterval
    let clearSeconds: TimeInterval

    private var trueSince: [String: TimeInterval] = [:]
    private var falseSince: [String: TimeInterval] = [:]
    private var activeSet: Set<String> = []

    init(order: [String], persistSeconds: TimeInterval, clearSeconds: TimeInterval) {
        self.order = order
        self.persistSeconds = persistSeconds
        self.clearSeconds = clearSeconds
    }

    var active: [String] { order.filter(activeSet.contains) }

    mutating func update(_ conditions: [String: Bool], at time: TimeInterval) {
        for id in order {
            if conditions[id] == true {
                falseSince[id] = nil
                let since = trueSince[id] ?? time
                trueSince[id] = since
                if time - since >= persistSeconds {
                    activeSet.insert(id)
                }
            } else {
                trueSince[id] = nil
                guard activeSet.contains(id) else { continue }
                let since = falseSince[id] ?? time
                falseSince[id] = since
                if time - since >= clearSeconds {
                    activeSet.remove(id)
                    falseSince[id] = nil
                }
            }
        }
    }
}

/// Time-weighted form score. Time spent not moving counts against the score;
/// time moving counts as clean when no fault is active.
///
/// score = movingFraction × (floor + (100 − floor) × cleanFraction)
/// The floor keeps scores encouraging: 70% clean with floor 25 lands at ~78.
struct ScoreAccumulator {
    let floor: Double
    /// Gaps longer than this (dropped frames, lost tracking) only count this much.
    var maxFrameGap: TimeInterval = 0.25

    private var lastTime: TimeInterval?
    private(set) var trackedTime: TimeInterval = 0
    private(set) var movingTime: TimeInterval = 0
    private(set) var cleanMovingTime: TimeInterval = 0

    init(floor: Double) {
        self.floor = floor
    }

    mutating func add(at time: TimeInterval, isMoving: Bool, isClean: Bool) {
        defer { lastTime = time }
        guard let last = lastTime else { return }
        let dt = min(max(time - last, 0), maxFrameGap)
        trackedTime += dt
        if isMoving {
            movingTime += dt
            if isClean { cleanMovingTime += dt }
        }
    }

    /// Frame without usable tracking: advances the clock without scoring it.
    mutating func skip(at time: TimeInterval) {
        lastTime = time
    }

    var score: Double {
        guard trackedTime > 0, movingTime > 0 else { return 0 }
        let movingFraction = movingTime / trackedTime
        let cleanFraction = cleanMovingTime / movingTime
        return min(100, movingFraction * (floor + (100 - floor) * cleanFraction))
    }
}

/// Values from the last `duration` seconds.
struct RollingWindow {
    let duration: TimeInterval
    private var samples: [(time: TimeInterval, value: Double)] = []

    init(duration: TimeInterval) {
        self.duration = duration
    }

    mutating func add(_ value: Double, at time: TimeInterval) {
        samples.append((time, value))
        if let firstKept = samples.firstIndex(where: { $0.time >= time - duration }) {
            samples.removeFirst(firstKept)
        }
    }

    var isEmpty: Bool { samples.isEmpty }
    var min: Double? { samples.map(\.value).min() }
    var max: Double? { samples.map(\.value).max() }
    var mean: Double? {
        samples.isEmpty ? nil : samples.reduce(0) { $0 + $1.value } / Double(samples.count)
    }
}

/// Counts back-and-forth motion in a 1D signal. The signal is compared against a
/// slow moving average, so it works wherever the user stands; crossing
/// ±`hysteresis` from that average on alternating sides is one half cycle.
struct OscillationCounter {
    let hysteresis: Double
    let baselineTimeConstant: TimeInterval

    private(set) var halfCycles = 0
    private(set) var lastTransitionTime: TimeInterval?
    private var baseline: Double?
    private var lastTime: TimeInterval?
    private var side = 0
    private var transitions: [TimeInterval] = []

    init(hysteresis: Double, baselineTimeConstant: TimeInterval = 2) {
        self.hysteresis = hysteresis
        self.baselineTimeConstant = baselineTimeConstant
    }

    var cycles: Int { halfCycles / 2 }

    /// Returns true when this sample completed a half cycle.
    @discardableResult
    mutating func update(_ value: Double, at time: TimeInterval) -> Bool {
        var base = baseline ?? value
        if let last = lastTime, time > last {
            base += (1 - exp(-(time - last) / baselineTimeConstant)) * (value - base)
        }
        baseline = base
        lastTime = time

        let offset = value - base
        let newSide = offset > hysteresis ? 1 : offset < -hysteresis ? -1 : side
        guard newSide != side else { return false }
        let completesHalfCycle = side != 0
        side = newSide
        guard completesHalfCycle else { return false }

        halfCycles += 1
        lastTransitionTime = time
        transitions.append(time)
        if transitions.count > 9 { transitions.removeFirst() }
        return true
    }

    /// Full cycles per minute over the recent transitions, nil if motion has stalled.
    func cyclesPerMinute(at time: TimeInterval) -> Double? {
        guard transitions.count >= 3, let first = transitions.first, let last = transitions.last,
              last > first, time - last < 3
        else { return nil }
        return Double(transitions.count - 1) / 2 / (last - first) * 60
    }
}
