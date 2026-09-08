import SwiftUI
import TipKit
import AppKit

@main
struct RingPodApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Owned here, because nothing else provides one.
    ///
    /// SwiftUI puts an `UndoManager` in the environment for document
    /// scenes. This is a plain `WindowGroup`, so `\.undoManager` was nil,
    /// every timeline edit registered its undo against nothing, and there
    /// was no Edit ▸ Undo item for ⌘Z to hit either — two halves of the
    /// same gap, which is why undo looked wired up and did nothing.
    @State private var undoManager = UndoManager()

    var body: some Scene {
        WindowGroup {
            // Passed rather than put in the environment: `\.undoManager`
            // is read-only, so a non-document app can't install one there.
            ContentView(undoManager: undoManager)
                .frame(minWidth: 1040, minHeight: 720)
                // TipKit keeps its own record of which tips have been shown
                // and dismissed, which is why nothing here owns a
                // "seen" flag. Configured at the window rather than in the
                // App's init so a failure can't take launch with it.
                .task {
                    try? Tips.configure([
                        .displayFrequency(.immediate),
                        .datastoreLocation(.applicationDefault),
                    ])
                }
        }
        .windowResizability(.contentSize)
        // Under Help, where macOS users look for "what changed". The
        // notification is what `ContentView` listens for — a command can't
        // reach into the window's own state directly.
        .commands {
            // The standard Edit ▸ Undo pair, which a document scene would
            // have brought along.
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { undoManager.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                Button("Redo") { undoManager.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .help) {
                Button("What's New in Nexus Pod") {
                    NotificationCenter.default.post(name: .showWhatsNew, object: nil)
                }
            }
        }
    }
}

/// Confirmed via live testing (clicking directly inside the app's own
/// window left the menu bar reading "Xcode", not "RingAnimator") that this
/// process never actually becomes the active application when Xcode
/// launches it -- clicks still hit-test into its window (so e.g. a text
/// field visibly gets a cursor), but keyboard events and trackpad gestures
/// keep routing to whatever WAS frontmost (Xcode), because the app is
/// never told to activate. This is the real root cause behind both the
/// text-input bug and the parked pinch-to-zoom bug -- a plain SwiftPM
/// executable launched outside a proper, LaunchServices-registered `.app`
/// bundle doesn't automatically get treated as a normal foreground GUI
/// app. `Package.swift`'s linker-embedded Info.plist (see the comment
/// there) fixes the *bundle identity* half of that gap; this fixes the
/// *activation* half.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
