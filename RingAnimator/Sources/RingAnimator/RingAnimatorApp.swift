import SwiftUI

@main
struct RingPodApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1040, minHeight: 720)
        }
        .windowResizability(.contentSize)
    }
}
