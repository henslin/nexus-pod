import SwiftUI
import TipKit

@main
struct RingPodApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                // See the Mac app for why this is here rather than in init.
                .task {
                    try? Tips.configure([
                        .displayFrequency(.immediate),
                        .datastoreLocation(.applicationDefault),
                    ])
                }
        }
    }
}
