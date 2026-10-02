import XCTest
@testable import MorningMonk

final class OneEuroFilterTests: XCTestCase {
    func testFirstSampleIsPassedThrough() {
        var filter = OneEuroFilter(minCutoff: 1, beta: 0)
        XCTAssertEqual(filter.filter(0.42, at: 0), 0.42)
    }

    func testReducesJitterOnStillSignal() {
        var filter = OneEuroFilter(minCutoff: 1.5, beta: 3)
        let noise = [0.01, -0.012, 0.008, -0.009, 0.011, -0.01, 0.009, -0.011]
        var rawSpread = 0.0, filteredSpread = 0.0
        var previousRaw = 0.5, previousFiltered = filter.filter(0.5, at: 0)
        for i in 0..<120 {
            let raw = 0.5 + noise[i % noise.count]
            let filtered = filter.filter(raw, at: Double(i + 1) / 30)
            rawSpread += abs(raw - previousRaw)
            filteredSpread += abs(filtered - previousFiltered)
            previousRaw = raw
            previousFiltered = filtered
        }
        XCTAssertLessThan(filteredSpread, rawSpread * 0.5)
    }

    func testTracksFastMovementWithLittleLag() {
        var filter = OneEuroFilter(minCutoff: 1.5, beta: 3)
        var output = 0.0
        // 2 units/second sweep at 30fps, the speed of a brisk arm swing.
        for i in 0...15 {
            let t = Double(i) / 30
            output = filter.filter(2 * t, at: t)
        }
        let target = 2 * 15.0 / 30
        XCTAssertEqual(output, target, accuracy: 0.1)
    }

    func testDuplicateTimestampReturnsPreviousValue() {
        var filter = OneEuroFilter(minCutoff: 1, beta: 0)
        let first = filter.filter(1, at: 1)
        XCTAssertEqual(filter.filter(5, at: 1), first)
    }

    func testSmootherResetsJointAfterGap() {
        let smoother = PoseSmoother()
        let a = [JointName.nose: Joint(position: CGPoint(x: 0.2, y: 0.2), confidence: 0.9)]
        let b = [JointName.nose: Joint(position: CGPoint(x: 0.8, y: 0.8), confidence: 0.9)]
        _ = smoother.smooth(a, at: 0)
        // Missing for a full second, then reappears elsewhere: should snap, not ease.
        let result = smoother.smooth(b, at: 1)
        XCTAssertEqual(result[.nose]?.position, CGPoint(x: 0.8, y: 0.8))
    }
}
