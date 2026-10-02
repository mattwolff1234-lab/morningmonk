import XCTest
@testable import MorningMonk

final class DetectorPrimitivesTests: XCTestCase {
    func testOscillationCounterCountsSineCycles() {
        var counter = OscillationCounter(hysteresis: 0.2)
        var t = 0.0
        while t < 10 {
            counter.update(sin(2 * .pi * t), at: t)
            t += 1.0 / 30
        }
        XCTAssertEqual(Double(counter.cycles), 9.5, accuracy: 1)
        XCTAssertEqual(counter.cyclesPerMinute(at: t) ?? 0, 60, accuracy: 3)
    }

    func testOscillationCounterIgnoresJitter() {
        var counter = OscillationCounter(hysteresis: 0.2)
        for i in 0..<300 {
            counter.update(i % 2 == 0 ? 0.05 : -0.05, at: Double(i) / 30)
        }
        XCTAssertEqual(counter.halfCycles, 0)
    }

    func testFaultMustPersistBeforeActivating() {
        var tracker = FaultTracker(order: ["x"], persistSeconds: 1.5, clearSeconds: 0.5)
        tracker.update(["x": true], at: 0)
        tracker.update(["x": true], at: 1.4)
        XCTAssertEqual(tracker.active, [])
        tracker.update(["x": true], at: 1.5)
        XCTAssertEqual(tracker.active, ["x"])
        // A brief dropout doesn't clear it.
        tracker.update(["x": false], at: 1.6)
        tracker.update(["x": true], at: 1.8)
        XCTAssertEqual(tracker.active, ["x"])
        tracker.update(["x": false], at: 2)
        tracker.update(["x": false], at: 2.5)
        XCTAssertEqual(tracker.active, [])
    }

    func testFaultFlickerNeverActivates() {
        var tracker = FaultTracker(order: ["x"], persistSeconds: 1.5, clearSeconds: 0.5)
        for i in 0..<100 {
            tracker.update(["x": i % 30 < 20], at: Double(i) / 30)
        }
        XCTAssertEqual(tracker.active, [])
    }

    func testScoreIsEncouraging() {
        var score = ScoreAccumulator(floor: 25)
        for i in 0...300 {
            // Moving the whole time, clean 70% of it.
            score.add(at: Double(i) / 30, isMoving: true, isClean: i % 10 < 7)
        }
        XCTAssertEqual(score.score, 77.5, accuracy: 1)
    }

    func testScoreIgnoresUntrackedFrames() {
        var score = ScoreAccumulator(floor: 25)
        score.add(at: 0, isMoving: true, isClean: true)
        score.add(at: 1.0 / 30, isMoving: true, isClean: true)
        score.skip(at: 5)
        score.add(at: 5 + 1.0 / 30, isMoving: true, isClean: true)
        XCTAssertEqual(score.score, 100, accuracy: 0.001)
    }

    func testRollingWindowDropsOldSamples() {
        var window = RollingWindow(duration: 1)
        window.add(10, at: 0)
        window.add(2, at: 0.5)
        window.add(4, at: 1.2)
        XCTAssertEqual(window.max, 4)
        XCTAssertEqual(window.min, 2)
        XCTAssertEqual(window.mean, 3)
    }
}
