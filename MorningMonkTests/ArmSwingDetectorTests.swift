import XCTest
@testable import MorningMonk

final class ArmSwingDetectorTests: XCTestCase {
    private typealias Fault = ArmSwingDetector.Fault

    private func run(_ swing: SyntheticArmSwing) throws -> DetectorHarness.Result {
        let move = try XCTUnwrap(MoveLibrary.load().move(id: ArmSwingDetector.moveID))
        return DetectorHarness.run(swing.frames(), through: ArmSwingDetector(definition: move))
    }

    func testGoodFormCountsSwingsWithNoFaults() throws {
        let result = try run(SyntheticArmSwing())
        XCTAssertEqual(result.faultsSeen, [])
        // 0.8 swings/s for 20s.
        XCTAssertEqual(Double(result.final.reps), 16, accuracy: 1)
        XCTAssertGreaterThanOrEqual(result.final.formScore, 85)
        XCTAssertTrue(result.final.isMoving)
    }

    func testArmsAboveShoulders() throws {
        let result = try run(SyntheticArmSwing(amplitudeDegrees: 125))
        XCTAssertEqual(result.faultsSeen, [Fault.armsTooHigh])
    }

    func testBentElbows() throws {
        let result = try run(SyntheticArmSwing(amplitudeDegrees: 60, elbowBendDegrees: 60))
        XCTAssertEqual(result.faultsSeen, [Fault.bentElbows])
    }

    func testNoKneeBounce() throws {
        let result = try run(SyntheticArmSwing(bounceEverySwings: nil))
        XCTAssertEqual(result.faultsSeen, [Fault.noBounce])
        // 8 swings at 0.8/s is 10s, plus 1.5s persistence.
        let firstActive = try XCTUnwrap(result.firstActive[Fault.noBounce])
        XCTAssertEqual(firstActive, 11.5, accuracy: 1.5)
    }

    func testFaultsLowerTheScoreButStayEncouraging() throws {
        let good = try run(SyntheticArmSwing()).final.formScore
        let sloppy = try run(SyntheticArmSwing(bounceEverySwings: nil)).final.formScore
        XCTAssertLessThan(sloppy, good)
        XCTAssertGreaterThan(sloppy, 50)
    }

    func testStandingStillIsNotScoredOrCorrected() throws {
        let result = try run(SyntheticArmSwing(amplitudeDegrees: 0, bounceEverySwings: nil))
        XCTAssertEqual(result.final.reps, 0)
        XCTAssertEqual(result.faultsSeen, [])
        XCTAssertEqual(result.final.formScore, 0)
        XCTAssertFalse(result.final.isMoving)
    }

    func testLostTrackingKeepsCountAndReportsNotTracking() throws {
        let move = try XCTUnwrap(MoveLibrary.load().move(id: ArmSwingDetector.moveID))
        let detector = ArmSwingDetector(definition: move)
        var frames = SyntheticArmSwing(duration: 10).frames()
        let last = frames.removeLast()
        let reps = DetectorHarness.run(frames, through: detector).final.reps
        XCTAssertGreaterThan(reps, 0)

        var blind = last
        blind.joints = [:]
        let output = detector.process(blind)
        XCTAssertFalse(output.isTracking)
        XCTAssertEqual(output.reps, reps)
    }

    func testResetClearsEverything() throws {
        let move = try XCTUnwrap(MoveLibrary.load().move(id: ArmSwingDetector.moveID))
        let detector = ArmSwingDetector(definition: move)
        _ = DetectorHarness.run(SyntheticArmSwing(bounceEverySwings: nil).frames(), through: detector)
        detector.reset()
        let output = detector.process(SyntheticArmSwing().frames()[0])
        XCTAssertEqual(output.reps, 0)
        XCTAssertEqual(output.activeFaults, [])
    }

    func testRecordingRoundTripReplaysIdentically() throws {
        let frames = SyntheticArmSwing(amplitudeDegrees: 125, duration: 8).frames()
        let recording = PoseRecording(moveID: ArmSwingDetector.moveID, recordedAt: Date(timeIntervalSince1970: 0), frames: frames)
        let data = try PoseRecording.encoder.encode(recording)
        let decoded = try PoseRecording.decoder.decode(PoseRecording.self, from: data)

        let move = try XCTUnwrap(MoveLibrary.load().move(id: ArmSwingDetector.moveID))
        let original = DetectorHarness.run(frames, through: ArmSwingDetector(definition: move))
        let replayed = DetectorHarness.run(decoded.frames, through: ArmSwingDetector(definition: move))
        XCTAssertEqual(original.final, replayed.final)
    }
}
