import XCTest
@testable import MorningMonk

final class PoseFrameTests: XCTestCase {
    /// 720x1280 portrait frame with shoulders 144px apart, centered at (360, 400).
    private func makeFrame() -> PoseFrame {
        func j(_ x: CGFloat, _ y: CGFloat) -> Joint {
            Joint(position: CGPoint(x: x / 720, y: y / 1280), confidence: 0.9)
        }
        return PoseFrame(
            timestamp: 0,
            imageSize: CGSize(width: 720, height: 1280),
            joints: [
                .leftShoulder: j(288, 400),
                .rightShoulder: j(432, 400),
                .rightElbow: j(432, 544),
                .rightWrist: j(576, 544),
                .leftWrist: j(288, 400 + 288),
            ]
        )
    }

    func testShoulderWidthIsInPixels() {
        XCTAssertEqual(makeFrame().shoulderWidth!, 144, accuracy: 0.001)
    }

    func testNormalizedPointIsInShoulderWidths() {
        let p = makeFrame().normalizedPoint(.leftWrist)!
        XCTAssertEqual(p.x, -0.5, accuracy: 0.001)
        XCTAssertEqual(p.y, 2, accuracy: 0.001)
    }

    func testNormalizedPointIsDistanceInvariant() {
        // Same pose, user twice as far away: everything half as big, shifted.
        var far = makeFrame()
        for (name, joint) in far.joints {
            far.joints[name]?.position = CGPoint(x: 0.25 + joint.position.x / 2, y: 0.25 + joint.position.y / 2)
        }
        let near = makeFrame().normalizedPoint(.rightWrist)!
        let farPoint = far.normalizedPoint(.rightWrist)!
        XCTAssertEqual(near.x, farPoint.x, accuracy: 0.001)
        XCTAssertEqual(near.y, farPoint.y, accuracy: 0.001)
    }

    func testCalibratedScaleOverridesFrameShoulderWidth() {
        let p = makeFrame().normalizedPoint(.leftWrist, scale: 288)!
        XCTAssertEqual(p.y, 1, accuracy: 0.001)
    }

    func testAngle() {
        let frame = makeFrame()
        XCTAssertEqual(frame.angle(at: .rightElbow, from: .rightShoulder, to: .rightWrist)!, 90, accuracy: 0.01)
        XCTAssertNil(frame.angle(at: .leftElbow, from: .leftShoulder, to: .leftWrist))
    }

    func testHasJoints() {
        let frame = makeFrame()
        XCTAssertTrue(frame.hasJoints([.leftShoulder, .rightShoulder], confidence: 0.5))
        XCTAssertFalse(frame.hasJoints([.leftShoulder, .leftAnkle], confidence: 0.5))
        XCTAssertFalse(frame.hasJoints([.leftShoulder], confidence: 0.95))
    }

    func testCodableRoundTripUsesJointNamesAsKeys() throws {
        let data = try JSONEncoder().encode(makeFrame())
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"leftShoulder\""))
        XCTAssertEqual(try JSONDecoder().decode(PoseFrame.self, from: data), makeFrame())
    }

    func testAspectFillTransform() {
        // 720x1280 image in a 400x800 view: scale 0.625 by height, overflows width.
        let t = AspectFillTransform(imageSize: CGSize(width: 720, height: 1280), viewSize: CGSize(width: 400, height: 800))
        XCTAssertEqual(t.viewPoint(fromNormalized: CGPoint(x: 0.5, y: 0.5)), CGPoint(x: 200, y: 400))
        let topLeft = t.viewPoint(fromNormalized: .zero)
        XCTAssertEqual(topLeft.x, -25, accuracy: 0.001)
        XCTAssertEqual(topLeft.y, 0, accuracy: 0.001)
    }
}
