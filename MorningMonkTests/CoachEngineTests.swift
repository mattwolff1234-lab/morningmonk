import XCTest
@testable import MorningMonk

final class CoachEngineTests: XCTestCase {
    private let config = CoachConfig(
        minSecondsBetweenCues: 6,
        faultRepeatSeconds: 12,
        praiseAfterFixSeconds: 2,
        cleanSilenceSeconds: 15,
        encouragement: ["Good.", "Nice."],
        openers: [],
        streak: []
    )

    private let move = MoveDefinition(
        id: "test",
        name: "Test",
        facing: .front,
        kind: .reps,
        durationSeconds: 60,
        thresholds: Thresholds([:]),
        faults: [
            FaultDefinition(id: "a", cues: ["A1", "A2", "A3"]),
            FaultDefinition(id: "b", cues: ["B1", "B2", "B3"]),
        ]
    )

    private func makeCoach() -> CoachEngine {
        CoachEngine(config: config, move: move)
    }

    func testCuesAFaultRightAway() {
        let coach = makeCoach()
        XCTAssertEqual(coach.update(activeFaults: ["a"], at: 0), CoachCue(kind: .correction(faultID: "a"), line: "A1"))
        XCTAssertEqual(coach.state, .correcting)
    }

    func testRateLimitsAllCues() {
        let coach = makeCoach()
        XCTAssertNotNil(coach.update(activeFaults: ["a"], at: 0))
        XCTAssertNil(coach.update(activeFaults: ["a", "b"], at: 3))
        XCTAssertNil(coach.update(activeFaults: ["a", "b"], at: 5.9))
        // "a" was just cued, so "b" gets its turn.
        XCTAssertEqual(coach.update(activeFaults: ["a", "b"], at: 6)?.line, "B1")
    }

    func testHigherPriorityFaultWins() {
        let coach = makeCoach()
        XCTAssertEqual(coach.update(activeFaults: ["b", "a"], at: 0)?.line, "A1")
    }

    func testRepeatedFaultRotatesPhrasing() {
        let coach = makeCoach()
        var lines: [String] = []
        for t in stride(from: 0.0, through: 40, by: 0.5) {
            if let cue = coach.update(activeFaults: ["a"], at: t) { lines.append(cue.line) }
        }
        XCTAssertEqual(lines, ["A1", "A2", "A3", "A1"])
    }

    func testNeverSaysTheSameLineTwiceInARow() {
        let coach = makeCoach()
        var lines: [String] = []
        // Alternate faults and fixes to exercise every path.
        for t in stride(from: 0.0, through: 200, by: 0.5) {
            let faults: [String] = Int(t / 9) % 3 == 0 ? ["a"] : Int(t / 9) % 3 == 1 ? [] : ["a", "b"]
            if let cue = coach.update(activeFaults: faults, at: t) { lines.append(cue.line) }
        }
        XCTAssertGreaterThan(lines.count, 10)
        for (previous, next) in zip(lines, lines.dropFirst()) {
            XCTAssertNotEqual(previous, next)
        }
    }

    func testPraisesAFixOnceRateLimitAllows() {
        let coach = makeCoach()
        XCTAssertNotNil(coach.update(activeFaults: ["a"], at: 0))
        XCTAssertNil(coach.update(activeFaults: [], at: 1))
        XCTAssertNil(coach.update(activeFaults: [], at: 3.5))
        XCTAssertEqual(coach.update(activeFaults: [], at: 6), CoachCue(kind: .encouragement, line: "Good."))
        XCTAssertNil(coach.update(activeFaults: [], at: 13))
    }

    func testStaysQuietAndNodsWhenFormIsClean() {
        let coach = makeCoach()
        for t in stride(from: 0.0, through: 30, by: 0.5) {
            XCTAssertNil(coach.update(activeFaults: [], at: t))
        }
        XCTAssertTrue(coach.isNodding)
        XCTAssertEqual(coach.state, .idle)
    }
}
