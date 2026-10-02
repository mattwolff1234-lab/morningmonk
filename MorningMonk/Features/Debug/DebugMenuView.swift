import SwiftUI

/// Entry point while the real app screens don't exist yet.
struct DebugMenuView: View {
    enum Route: Hashable {
        case pose
        case move(String)
    }

    private static let library = Result { try MoveLibrary.load() }
    private static let coachConfig = Result { try CoachConfig.load() }

    var body: some View {
        NavigationStack {
            List {
                Section("M1") {
                    NavigationLink("Pose tracking", value: Route.pose)
                }
                Section("M2 · moves") {
                    switch Self.library {
                    case .success(let library):
                        ForEach(library.moves) { move in
                            NavigationLink(move.name, value: Route.move(move.id))
                        }
                    case .failure(let error):
                        Text(error.localizedDescription).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Morning Monk")
            .navigationDestination(for: Route.self) { route in
                destination(route)
            }
        }
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .pose:
            PoseDebugView()
        case .move(let id):
            if let move = try? Self.library.get().move(id: id),
               let config = try? Self.coachConfig.get(),
               let detector = DetectorFactory.make(for: move) {
                MoveDebugView(move: move, coachConfig: config, detector: detector)
            } else {
                Text("No detector for \(id) yet.")
            }
        }
    }
}
