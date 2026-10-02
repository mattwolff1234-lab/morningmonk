import AVFoundation
import Observation

/// Camera + pose estimation for any screen that needs live `PoseFrame`s.
@MainActor
@Observable
final class PoseCaptureModel {
    enum CameraState: Equatable {
        case idle
        case needsPermission
        case denied
        case running
        case failed(String)
    }

    private(set) var state: CameraState = .idle
    private(set) var frame: PoseFrame?
    private(set) var diagnostics: PoseDiagnostics?

    /// Called on the main actor for every processed frame.
    @ObservationIgnored var onFrame: (@MainActor (PoseFrame) -> Void)?

    let camera = CameraManager()
    private let estimator = PoseEstimator()

    init() {
        estimator.onFrame = { [weak self] frame, diagnostics in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.frame = frame
                self.diagnostics = diagnostics
                self.onFrame?(frame)
            }
        }
    }

    func start() async {
        switch CameraManager.authorizationStatus {
        case .authorized:
            await startCamera()
        case .notDetermined:
            state = .needsPermission
        default:
            state = .denied
        }
    }

    func requestPermission() async {
        if await CameraManager.requestAccess() {
            await startCamera()
        } else {
            state = .denied
        }
    }

    func stop() {
        camera.stop()
        estimator.reset()
        frame = nil
        diagnostics = nil
        if state == .running { state = .idle }
    }

    private func startCamera() async {
        do {
            try await camera.start(delegate: estimator)
            state = .running
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
