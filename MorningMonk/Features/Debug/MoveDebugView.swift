import SwiftUI

/// M2 screen: live detector output for one move, coach cues, and frame recording.
struct MoveDebugView: View {
    @State private var model: MoveDebugModel

    init(move: MoveDefinition, coachConfig: CoachConfig, detector: MoveDetector) {
        _model = State(initialValue: MoveDebugModel(move: move, coachConfig: coachConfig, detector: detector))
    }

    var body: some View {
        PoseCameraView(capture: model.capture) {
            VStack(alignment: .leading, spacing: 8) {
                panel
                Spacer()
                if !model.cueLog.isEmpty {
                    cues
                }
                controls
            }
            .padding()
        }
        .navigationTitle(model.move.name)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { model.stopSpeaking() }
    }

    private var panel: some View {
        let out = model.output
        return VStack(alignment: .leading, spacing: 3) {
            Text(model.move.facing.instruction)
                .foregroundStyle(.yellow)
            Text("reps \(out.reps) · score \(Int(out.formScore.rounded()))")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
            Text("\(out.isTracking ? "tracking" : "NOT TRACKING") · \(out.isMoving ? "moving" : "still")")
            Text("monk: \(model.monkState.rawValue)\(model.isNodding ? " (nodding)" : "")")
            Text(String(format: "detector %.2f ms", model.detectorMs))

            Divider().overlay(Color.white.opacity(0.4))
            ForEach(out.metrics) { metric in
                HStack {
                    Text(metric.name)
                    Spacer()
                    Text(metric.value)
                }
            }

            Divider().overlay(Color.white.opacity(0.4))
            ForEach(model.move.faults, id: \.id) { fault in
                let active = out.activeFaults.contains(fault.id)
                let condition = out.faultConditions[fault.id] == true
                HStack(spacing: 6) {
                    Circle()
                        .fill(active ? Color.red : condition ? Color.yellow : Color.white.opacity(0.25))
                        .frame(width: 8, height: 8)
                    Text(fault.id)
                        .fontWeight(active ? Font.Weight.bold : Font.Weight.regular)
                }
            }
        }
        .font(.system(size: 12, design: .monospaced))
        .foregroundStyle(.white)
        .frame(width: 240, alignment: .leading)
        .padding(10)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }

    private var cues: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(model.cueLog.enumerated()), id: \.offset) { index, line in
                Text("\"\(line)\"")
                    .font(index == 0 ? .headline : .caption)
                    .opacity(index == 0 ? 1 : 0.6)
            }
        }
        .foregroundStyle(.white)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }

    private var controls: some View {
        HStack {
            Button("Reset") { model.reset() }
            Toggle("Voice", isOn: $model.voiceOn)
                .toggleStyle(.button)
            Button(model.isRecording ? "Stop (\(model.recordedFrameCount))" : "Record") {
                model.toggleRecording()
            }
            .tint(model.isRecording ? Color.red : Color.black.opacity(0.6))
            if let url = model.exportURL {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(.black.opacity(0.6))
        .frame(maxWidth: .infinity)
    }
}
