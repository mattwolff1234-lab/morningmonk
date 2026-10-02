import CoreGraphics
import Foundation

/// One Euro filter (Casiez et al. 2012): heavy smoothing when a signal is still,
/// light smoothing when it moves fast, so jitter dies without adding lag to swings.
struct OneEuroFilter {
    /// Cutoff (Hz) when the signal is still. Lower = smoother, laggier at rest.
    var minCutoff: Double
    /// How fast the cutoff rises with speed. Higher = less lag on fast moves.
    var beta: Double
    /// Cutoff (Hz) for the derivative estimate.
    var derivativeCutoff: Double

    private var previousValue: Double?
    private var previousDerivative: Double = 0
    private var previousTime: TimeInterval?

    init(minCutoff: Double, beta: Double, derivativeCutoff: Double = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.derivativeCutoff = derivativeCutoff
    }

    mutating func filter(_ value: Double, at time: TimeInterval) -> Double {
        guard let lastValue = previousValue, let lastTime = previousTime else {
            previousValue = value
            previousTime = time
            previousDerivative = 0
            return value
        }
        let dt = time - lastTime
        guard dt > 0 else { return lastValue }

        let derivative = (value - lastValue) / dt
        let smoothedDerivative = Self.lowPass(previousDerivative, derivative, alpha: Self.alpha(dt: dt, cutoff: derivativeCutoff))
        let cutoff = minCutoff + beta * abs(smoothedDerivative)
        let result = Self.lowPass(lastValue, value, alpha: Self.alpha(dt: dt, cutoff: cutoff))

        previousValue = result
        previousDerivative = smoothedDerivative
        previousTime = time
        return result
    }

    mutating func reset() {
        previousValue = nil
        previousTime = nil
        previousDerivative = 0
    }

    private static func alpha(dt: Double, cutoff: Double) -> Double {
        let tau = 1 / (2 * .pi * cutoff)
        return 1 / (1 + tau / dt)
    }

    private static func lowPass(_ previous: Double, _ value: Double, alpha: Double) -> Double {
        previous + alpha * (value - previous)
    }
}

/// Smooths every joint of a pose independently. Not thread-safe; use from one queue.
final class PoseSmoother {
    struct Parameters {
        // Tuned for normalized (0-1) image coordinates, where a fast arm swing moves
        // roughly 1-3 units per second.
        var minCutoff: Double = 1.5
        var beta: Double = 3.0
        var derivativeCutoff: Double = 1.0
        /// A joint missing longer than this restarts its filter instead of easing in
        /// from a stale position.
        var resetAfter: TimeInterval = 0.5
    }

    var parameters: Parameters
    private var filters: [JointName: (x: OneEuroFilter, y: OneEuroFilter)] = [:]
    private var lastSeen: [JointName: TimeInterval] = [:]

    init(parameters: Parameters = Parameters()) {
        self.parameters = parameters
    }

    func smooth(_ joints: [JointName: Joint], at time: TimeInterval) -> [JointName: Joint] {
        var output: [JointName: Joint] = [:]
        for (name, joint) in joints {
            var pair = filters[name] ?? makeFilters()
            if let seen = lastSeen[name], time - seen > parameters.resetAfter {
                pair.x.reset()
                pair.y.reset()
            }
            let x = pair.x.filter(Double(joint.position.x), at: time)
            let y = pair.y.filter(Double(joint.position.y), at: time)
            filters[name] = pair
            lastSeen[name] = time
            output[name] = Joint(position: CGPoint(x: x, y: y), confidence: joint.confidence)
        }
        return output
    }

    func reset() {
        filters.removeAll()
        lastSeen.removeAll()
    }

    private func makeFilters() -> (x: OneEuroFilter, y: OneEuroFilter) {
        let f = OneEuroFilter(minCutoff: parameters.minCutoff, beta: parameters.beta, derivativeCutoff: parameters.derivativeCutoff)
        return (f, f)
    }
}
