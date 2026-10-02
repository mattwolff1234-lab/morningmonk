import AVFoundation
import QuartzCore
import Vision

/// Per-frame numbers for the debug HUD. Not used by detectors.
struct PoseDiagnostics: Sendable {
    /// Confidence of every joint Vision reported, including ones below the threshold.
    var rawConfidences: [JointName: Float]
    /// Vision + smoothing time for this frame.
    var processingMs: Double
    var averageProcessingMs: Double
    /// 1 = every frame analyzed, 2 = every 2nd frame (over budget).
    var frameStride: Int
    var cameraFPS: Double
    var poseFPS: Double
    var personDetected: Bool
}

/// Runs Vision body pose on camera frames and emits smoothed `PoseFrame`s.
///
/// Everything here runs on the camera's video queue. `onFrame` is called on that queue.
final class PoseEstimator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onFrame: ((PoseFrame, PoseDiagnostics) -> Void)?

    /// Joints below this are dropped before smoothing.
    var minimumConfidence: Float = 0.3
    /// Per-frame budget for pose work. Above it, only every 2nd frame is analyzed.
    var frameBudgetMs: Double = 20

    private let request = VNDetectHumanBodyPoseRequest()
    private let smoother = PoseSmoother()

    private var frameCounter = 0
    private var frameStride = 1
    private var averageMs: Double = 0
    private var cameraTimes = RollingRate()
    private var poseTimes = RollingRate()

    func reset() {
        smoother.reset()
        frameCounter = 0
        frameStride = 1
        averageMs = 0
        cameraTimes = RollingRate()
        poseTimes = RollingRate()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let cameraFPS = cameraTimes.tick(timestamp)

        frameCounter &+= 1
        guard frameCounter % frameStride == 0,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }

        let start = CACurrentMediaTime()
        let imageSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))

        // Frames arrive already rotated upright by the capture connection.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        var observation: VNHumanBodyPoseObservation?
        do {
            try handler.perform([request])
            observation = Self.mostConfidentPerson(in: request.results ?? [])
        } catch {
            observation = nil
        }

        var rawConfidences: [JointName: Float] = [:]
        var joints: [JointName: Joint] = [:]
        if let observation, let points = try? observation.recognizedPoints(.all) {
            for name in JointName.allCases {
                guard let point = points[name.visionName] else { continue }
                rawConfidences[name] = point.confidence
                guard point.confidence >= minimumConfidence else { continue }
                // Vision: origin bottom-left, unmirrored. Display: origin top-left, mirrored.
                joints[name] = Joint(
                    position: CGPoint(x: 1 - point.location.x, y: 1 - point.location.y),
                    confidence: point.confidence
                )
            }
        }

        let smoothed = smoother.smooth(joints, at: timestamp)
        let elapsedMs = (CACurrentMediaTime() - start) * 1000
        updateStride(elapsedMs)

        let frame = PoseFrame(timestamp: timestamp, imageSize: imageSize, joints: smoothed)
        let diagnostics = PoseDiagnostics(
            rawConfidences: rawConfidences,
            processingMs: elapsedMs,
            averageProcessingMs: averageMs,
            frameStride: frameStride,
            cameraFPS: cameraFPS,
            poseFPS: poseTimes.tick(timestamp),
            personDetected: observation != nil
        )
        onFrame?(frame, diagnostics)
    }

    /// Picks the person Vision is surest about when more than one is in frame.
    private static func mostConfidentPerson(in observations: [VNHumanBodyPoseObservation]) -> VNHumanBodyPoseObservation? {
        observations.max { totalConfidence($0) < totalConfidence($1) }
    }

    private static func totalConfidence(_ observation: VNHumanBodyPoseObservation) -> Float {
        guard let points = try? observation.recognizedPoints(.all) else { return 0 }
        return points.values.reduce(0) { $0 + $1.confidence }
    }

    private func updateStride(_ elapsedMs: Double) {
        averageMs = averageMs == 0 ? elapsedMs : averageMs * 0.9 + elapsedMs * 0.1
        if frameStride == 1, averageMs > frameBudgetMs {
            frameStride = 2
        } else if frameStride == 2, averageMs < frameBudgetMs * 0.6 {
            frameStride = 1
        }
    }
}

/// Events per second over the trailing one-second window.
struct RollingRate {
    private var times: [TimeInterval] = []

    mutating func tick(_ time: TimeInterval) -> Double {
        times.append(time)
        times.removeAll { $0 <= time - 1 }
        return Double(times.count)
    }
}

extension JointName {
    var visionName: VNHumanBodyPoseObservation.JointName {
        switch self {
        case .nose: .nose
        case .leftEye: .leftEye
        case .rightEye: .rightEye
        case .leftEar: .leftEar
        case .rightEar: .rightEar
        case .neck: .neck
        case .leftShoulder: .leftShoulder
        case .rightShoulder: .rightShoulder
        case .leftElbow: .leftElbow
        case .rightElbow: .rightElbow
        case .leftWrist: .leftWrist
        case .rightWrist: .rightWrist
        case .root: .root
        case .leftHip: .leftHip
        case .rightHip: .rightHip
        case .leftKnee: .leftKnee
        case .rightKnee: .rightKnee
        case .leftAnkle: .leftAnkle
        case .rightAnkle: .rightAnkle
        }
    }
}
