import SwiftUI
import AppKit

@main
struct RingPodApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1040, minHeight: 720)
        }
        .windowResizability(.contentSize)
        // Under Help, where macOS users look for "what changed". The
        // notification is what `ContentView` listens for — a command can't
        // reach into the window's own state directly.
        .commands {
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
public extension Notification.Name {
    /// Posted by the Help menu item; `ContentView` presents the sheet.
    static let showWhatsNew = Notification.Name("nexus.showWhatsNew")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
