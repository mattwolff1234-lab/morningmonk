import SwiftUI

/// Full-screen camera with the skeleton, permission handling and lifecycle.
/// Screens put their own HUD on top via `overlay`.
struct PoseCameraView<Overlay: View>: View {
    let capture: PoseCaptureModel
    let showSkeleton: Bool
    let overlay: () -> Overlay

    init(capture: PoseCaptureModel, showSkeleton: Bool = true, @ViewBuilder overlay: @escaping () -> Overlay) {
        self.capture = capture
        self.showSkeleton = showSkeleton
        self.overlay = overlay
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch capture.state {
            case .idle, .running:
                CameraPreview(session: capture.camera.session, isRunning: capture.state == .running)
                    .ignoresSafeArea()
                if showSkeleton, let frame = capture.frame {
                    SkeletonOverlay(frame: frame)
                        .ignoresSafeArea()
                }
                overlay()
            case .needsPermission:
                permissionPrompt
            case .denied:
                message("Camera access is off. Turn it on in Settings so the monk can see your form.")
            case .failed(let reason):
                message(reason)
            }
        }
        .task { await capture.start() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: Task { await capture.start() }
            case .background: capture.stop()
            default: break
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            capture.stop()
        }
    }

    private var permissionPrompt: some View {
        VStack(spacing: 20) {
            Text("The monk needs to see you")
                .font(.title2.bold())
            Text("Your camera stays on your phone. Nothing is recorded or uploaded.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Allow camera") {
                Task { await capture.requestPermission() }
            }
            .buttonStyle(.borderedProminent)
        }
        .foregroundStyle(.white)
        .padding(32)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(32)
    }
}
