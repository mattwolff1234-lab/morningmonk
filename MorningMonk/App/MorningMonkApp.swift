import SwiftUI

@main
struct MorningMonkApp: App {
    var body: some Scene {
        WindowGroup {
            if Self.isRunningTests {
                // Unit tests use the app as a host; keep the camera off.
                Color.clear
            } else {
                PoseDebugView()
                    .preferredColorScheme(.dark)
            }
        }
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
