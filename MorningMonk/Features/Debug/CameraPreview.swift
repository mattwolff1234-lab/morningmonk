import AVFoundation
import SwiftUI

/// Live camera feed, aspect-filled and mirrored like a selfie camera.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    /// Passed so the view updates once the session has a connection to rotate.
    let isRunning: Bool

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.applyPortraitRotation()
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // Safe: layerClass guarantees the type.
            layer as! AVCaptureVideoPreviewLayer
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            applyPortraitRotation()
        }

        func applyPortraitRotation() {
            guard let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90) else { return }
            connection.videoRotationAngle = 90
        }
    }
}
