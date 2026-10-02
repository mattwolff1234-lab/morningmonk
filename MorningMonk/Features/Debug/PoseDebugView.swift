import SwiftUI

/// M1 screen: camera feed, skeleton, FPS/latency HUD, joint confidence panel.
struct PoseDebugView: View {
    @State private var model = PoseDebugModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch model.state {
            case .idle, .running:
                cameraLayer
            case .needsPermission:
                permissionPrompt
            case .denied:
                message("Camera access is off. Turn it on in Settings so the monk can see your form.")
            case .failed(let reason):
                message(reason)
            }
        }
        .task { await model.start() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: Task { await model.start() }
            case .background: model.stop()
            default: break
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            model.stop()
        }
    }

    private var cameraLayer: some View {
        ZStack {
            CameraPreview(session: model.camera.session, isRunning: model.state == .running)
                .ignoresSafeArea()

            if model.showSkeleton, let frame = model.frame {
                SkeletonOverlay(frame: frame)
                    .ignoresSafeArea()
            }

            VStack(alignment: .leading, spacing: 8) {
                hud
                if model.showConfidencePanel, let diagnostics = model.diagnostics {
                    JointConfidenceView(confidences: diagnostics.rawConfidences, threshold: 0.3)
                }
                Spacer()
                controls
            }
            .padding()
        }
    }

    private var hud: some View {
        let d = model.diagnostics
        return VStack(alignment: .leading, spacing: 2) {
            Text("cam \(Int(d?.cameraFPS ?? 0)) fps · pose \(Int(d?.poseFPS ?? 0)) fps")
            Text(String(format: "pose %.1f ms (avg %.1f) · stride %d", d?.processingMs ?? 0, d?.averageProcessingMs ?? 0, d?.frameStride ?? 1))
            Text(d?.personDetected == true ? "person: yes · \(model.frame?.joints.count ?? 0)/19 joints" : "person: no")
        }
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .foregroundStyle(.white)
        .padding(8)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }

    private var controls: some View {
        HStack {
            Toggle("Skeleton", isOn: $model.showSkeleton)
            Toggle("Joints", isOn: $model.showConfidencePanel)
        }
        .toggleStyle(.button)
        .buttonStyle(.borderedProminent)
        .tint(.black.opacity(0.6))
        .frame(maxWidth: .infinity)
    }

    private var permissionPrompt: some View {
        VStack(spacing: 20) {
            Text("The monk needs to see you")
                .font(.title2.bold())
            Text("Your camera stays on your phone. Nothing is recorded or uploaded.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Allow camera") {
                Task { await model.requestPermission() }
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
