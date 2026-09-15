import SwiftUI
import RingAnimatorCore

/// Nexus Lab — the team viewer. Every Lab experiment full screen,
/// reacting to the room's voice, with a rating and a note per option.
/// The whole app is `LabViewerView` from RingAnimatorCore; this file is
/// the shell. See that view's header for what it is for.
@main
struct NexusLabApp: App {
    var body: some Scene {
        WindowGroup {
            LabViewerView()
        }
    }
}
