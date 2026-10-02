import XCTest
@testable import MorningMonk

/// Guards the JSON files: tuning them should never be able to crash the app.
final class MoveLibraryTests: XCTestCase {
    func testEveryMoveWithADetectorHasItsThresholds() throws {
        let library = try MoveLibrary.load()
        let armSwings = try XCTUnwrap(library.move(id: ArmSwingDetector.moveID))
        XCTAssertEqual(armSwings.thresholds.missing(ArmSwingDetector.requiredThresholds), [])
        XCTAssertNotNil(DetectorFactory.make(for: armSwings))
    }

    func testArmSwingFaultsMatchDetector() throws {
        let move = try XCTUnwrap(MoveLibrary.load().move(id: ArmSwingDetector.moveID))
        typealias Fault = ArmSwingDetector.Fault
        XCTAssertEqual(Set(move.faults.map(\.id)), [Fault.armsTooHigh, Fault.bentElbows, Fault.noBounce])
    }

    func testEveryCueHasAtLeastThreeVariants() throws {
        for move in try MoveLibrary.load().moves {
            for fault in move.faults {
                XCTAssertGreaterThanOrEqual(fault.cues.count, 3, "\(move.id).\(fault.id)")
                XCTAssertEqual(Set(fault.cues).count, fault.cues.count, "duplicate cue in \(move.id).\(fault.id)")
            }
        }
    }

    func testCoachConfigLoads() throws {
        let config = try CoachConfig.load()
        XCTAssertGreaterThanOrEqual(config.encouragement.count, 3)
        XCTAssertTrue(config.streak.allSatisfy { $0.contains("{day}") })
        XCTAssertGreaterThanOrEqual(config.minSecondsBetweenCues, 6)
    }

    func testNoBannedClaimsInSpokenLines() throws {
        let banned = ["lymph", "detox", "drain", "fat", "weight", "burn", "cure", "heal"]
        var lines = try CoachConfig.load().encouragement
        for move in try MoveLibrary.load().moves {
            lines += move.faults.flatMap(\.cues)
        }
        for line in lines {
            for word in banned {
                XCTAssertFalse(line.lowercased().contains(word), "\"\(line)\" contains \"\(word)\"")
            }
        }
    }
}
