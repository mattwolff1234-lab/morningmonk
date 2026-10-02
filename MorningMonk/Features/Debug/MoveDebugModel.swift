import Foundation
import Observation
import QuartzCore

/// Runs one move's detector and the coach on live frames, and records frames for the
/// test harness.
@MainActor
@Observable
final class MoveDebugModel {
    let move: MoveDefinition
    let capture = PoseCaptureModel()

    private(set) var output = MoveDetectorOutput()
    private(set) var cueLog: [String] = []
    private(set) var monkState: MonkState = .idle
    private(set) var isNodding = false
    private(set) var detectorMs: Double = 0
    var voiceOn = true

    private(set) var isRecording = false
    private(set) var recordedFrameCount = 0
    private(set) var exportURL: URL?
    private(set) var exportError: String?

    private let detector: MoveDetector
    private let coach: CoachEngine
    private let speaker = CueSpeaker()
    @ObservationIgnored private var recorded: [PoseFrame] = []

    init(move: MoveDefinition, coachConfig: CoachConfig, detector: MoveDetector) {
        self.move = move
        self.detector = detector
        self.coach = CoachEngine(config: coachConfig, move: move)
        capture.onFrame = { [weak self] frame in
            self?.handle(frame)
        }
    }

    func reset() {
        detector.reset()
        coach.reset()
        output = MoveDetectorOutput()
        cueLog = []
    }

    func stopSpeaking() {
        speaker.stop()
    }

    func toggleRecording() {
        if isRecording {
            isRecording = false
            export()
        } else {
            recorded = []
            recordedFrameCount = 0
            exportURL = nil
            exportError = nil
            isRecording = true
        }
    }

    private func handle(_ frame: PoseFrame) {
        let start = CACurrentMediaTime()
        output = detector.process(frame)
        detectorMs = (CACurrentMediaTime() - start) * 1000

        if let cue = coach.update(activeFaults: output.activeFaults, at: frame.timestamp) {
            cueLog.insert(cue.line, at: 0)
            if cueLog.count > 4 { cueLog.removeLast() }
            if voiceOn { speaker.speak(cue.line) }
        }
        monkState = coach.state
        isNodding = coach.isNodding

        if isRecording {
            recorded.append(frame)
            recordedFrameCount = recorded.count
        }
    }

    private func export() {
        let recording = PoseRecording(moveID: move.id, recordedAt: Date(), frames: recorded)
        let name = "\(move.id)-\(Int(Date().timeIntervalSince1970)).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try PoseRecording.encoder.encode(recording).write(to: url)
            exportURL = url
        } catch {
            exportError = error.localizedDescription
        }
    }
}
