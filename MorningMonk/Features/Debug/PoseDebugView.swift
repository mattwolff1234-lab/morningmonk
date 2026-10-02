import SwiftUI

/// M1 screen: camera feed, skeleton, FPS/latency HUD, joint confidence panel.
struct PoseDebugView: View {
    @State private var capture = PoseCaptureModel()
    @State private var showSkeleton = true
    @State private var showConfidencePanel = false

    var body: some View {
        PoseCameraView(capture: capture, showSkeleton: showSkeleton) {
            VStack(alignment: .leading, spacing: 8) {
                hud
                if showConfidencePanel, let diagnostics = capture.diagnostics {
                    JointConfidenceView(confidences: diagnostics.rawConfidences, threshold: 0.3)
                }
                Spacer()
                HStack {
                    Toggle("Skeleton", isOn: $showSkeleton)
                    Toggle("Joints", isOn: $showConfidencePanel)
                }
                .toggleStyle(.button)
                .buttonStyle(.borderedProminent)
                .tint(.black.opacity(0.6))
                .frame(maxWidth: .infinity)
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hud: some View {
        let d = capture.diagnostics
        return VStack(alignment: .leading, spacing: 2) {
            Text("cam \(Int(d?.cameraFPS ?? 0)) fps · pose \(Int(d?.poseFPS ?? 0)) fps")
            Text(String(format: "pose %.1f ms (avg %.1f) · stride %d", d?.processingMs ?? 0, d?.averageProcessingMs ?? 0, d?.frameStride ?? 1))
            Text(d?.personDetected == true ? "person: yes · \(capture.frame?.joints.count ?? 0)/19 joints" : "person: no")
        }
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .foregroundStyle(.white)
        .padding(8)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }
}
