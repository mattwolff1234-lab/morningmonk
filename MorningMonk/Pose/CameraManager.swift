import AVFoundation

enum CameraError: LocalizedError {
    case noFrontCamera
    case cannotAddInput
    case cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .noFrontCamera: "This device has no front camera."
        case .cannotAddInput: "Couldn't connect to the front camera."
        case .cannotAddOutput: "Couldn't read frames from the camera."
        }
    }
}

/// Owns the capture session: front camera, portrait, 30fps.
///
/// Frames are delivered upright and unmirrored, so Vision's left/right labels match
/// the user's real left/right. `PoseEstimator` mirrors coordinates for display.
final class CameraManager {
    static let targetFrameRate: Int32 = 30
    /// The app is portrait-locked; the sensor is landscape, so frames rotate 90°.
    private static let portraitRotation: CGFloat = 90

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "morningmonk.camera.session")
    private let videoQueue = DispatchQueue(label: "morningmonk.camera.video", qos: .userInteractive)
    private let videoOutput = AVCaptureVideoDataOutput()
    private var isConfigured = false

    static var authorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    func start(delegate: AVCaptureVideoDataOutputSampleBufferDelegate) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try self.configureIfNeeded(delegate: delegate)
                    if !self.session.isRunning {
                        self.session.startRunning()
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    private func configureIfNeeded(delegate: AVCaptureVideoDataOutputSampleBufferDelegate) throws {
        guard !isConfigured else { return }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .hd1280x720

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            throw CameraError.noFrontCamera
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
        session.addInput(input)

        lockFrameRate(device)

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(delegate, queue: videoQueue)
        guard session.canAddOutput(videoOutput) else { throw CameraError.cannotAddOutput }
        session.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(Self.portraitRotation) {
                connection.videoRotationAngle = Self.portraitRotation
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        }

        isConfigured = true
    }

    private func lockFrameRate(_ device: AVCaptureDevice) {
        let duration = CMTime(value: 1, timescale: Self.targetFrameRate)
        let supported = device.activeFormat.videoSupportedFrameRateRanges.contains {
            $0.minFrameRate <= Double(Self.targetFrameRate) && Double(Self.targetFrameRate) <= $0.maxFrameRate
        }
        guard supported, (try? device.lockForConfiguration()) != nil else { return }
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
        device.unlockForConfiguration()
    }
}
