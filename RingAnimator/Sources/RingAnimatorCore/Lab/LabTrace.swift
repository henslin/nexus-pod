import Foundation

/// A trace of Q Branch's selection and play, to a file — on only when
/// `nexus.lab.trace` is set (`defaults write ringanimator.RingAnimator.dev
/// nexus.lab.trace -bool YES`). For chasing what the app does that the
/// harness can't reproduce: the sidebar's click.
import SwiftUI

/// Log a view's frame in the window, once, under a name.
struct LabTraceFrame: ViewModifier {
    let name: String
    func body(content: Content) -> some View {
        content.background(GeometryReader { g in
            Color.clear.onAppear { LabTrace.log("frame \(name): \(g.frame(in: .global))") }
        })
    }
}
extension View { func traceFrame(_ name: String) -> some View { modifier(LabTraceFrame(name: name)) } }

enum LabTrace {
    static let on = UserDefaults.standard.bool(forKey: "nexus.lab.trace")
    static let url = URL(fileURLWithPath: "/tmp/nexus-lab-trace.log")
    static func log(_ s: @autoclosure () -> String) {
        guard on else { return }
        let line = "\(Date().formatted(date: .omitted, time: .standard)) \(s())\n"
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
        else { try? line.write(to: url, atomically: true, encoding: .utf8) }
    }
}
