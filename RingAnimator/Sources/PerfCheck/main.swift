import Foundation
import SwiftUI
import AppKit
import RingAnimatorCore

// What each piece of the UI costs to draw one frame.
//
// Sampling the running app tells you which symbols are hot but not what to
// do about it, because the answer depends on how many of each thing are on
// screen. This times the pieces separately so "69 rows at 12fps" and "one
// stage ring at 60fps" can be compared in the same units: milliseconds of
// main-thread work per second of wall clock.
@MainActor
func timeFrames(_ label: String, count: Int, fps: Double, build: (Int) -> AnyView) {
    // One warm-up pass: the first render of any view type pays for SwiftUI
    // building its type metadata, which would otherwise land entirely on
    // whichever case ran first.
    for i in 0..<min(count, 3) {
        let r = ImageRenderer(content: build(i)); r.scale = 2; _ = r.cgImage
    }
    let frames = 60
    let start = Date()
    for i in 0..<frames {
        let r = ImageRenderer(content: build(i)); r.scale = 2; _ = r.cgImage
    }
    let perFrame = Date().timeIntervalSince(start) / Double(frames) * 1000
    let perSecond = perFrame * fps * Double(count)
    print(String(format: "  %-34@ %6.2f ms x %3d @ %2.0ffps = %7.1f ms/s",
                 label as NSString, perFrame, count, fps, perSecond))
}

@MainActor
func run() -> Int32 {
    let patterns = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Claude/patterns")
    let text = BlenderScriptImporter.readScriptFollowingDelegation(
        at: patterns.appendingPathComponent("spinning_rainbow.py"))?.text

    func config(_ setUp: (RingConfig) -> Void) -> RingConfig {
        let c = RingConfig()
        if let text { _ = BlenderScriptImporter.apply(text, to: c) }
        setUp(c)
        return c
    }

    // What one `RingConfig` costs to exist.
    //
    // Every thumbnail row, every timeline step and every cue preview owns
    // one as a `@StateObject`, and its initializer reads the Keychain and
    // builds a voice service, a conversation controller and a Combine
    // pipeline. A sidebar is a hundred of them.
    do {
        let start = Date()
        var keep: [RingConfig] = []
        for _ in 0..<100 { keep.append(RingConfig()) }
        let each = Date().timeIntervalSince(start) / 100 * 1000
        print(String(format: "  one RingConfig() costs %.3f ms — %.0f ms for a sidebar of 100\n",
                     each, each * 100))
        _ = keep.count
    }

    print("main-thread cost per second of wall clock:\n")

    // The floor. ImageRenderer has fixed per-call overhead, and if that
    // dominates then every number below is measuring the harness rather
    // than the view — so this has to be read first.
    timeFrames("BASELINE: empty 28pt view", count: 1, fps: 12) { _ in
        AnyView(Color.clear.frame(width: 28, height: 28))
    }
    timeFrames("BASELINE: one stroked circle 28pt", count: 1, fps: 12) { i in
        AnyView(Circle().stroke(Color.blue, lineWidth: 3)
            .rotationEffect(.degrees(Double(i) * 6))
            .frame(width: 28, height: 28))
    }


    let stage = config { _ in }
    timeFrames("stage ring, 200pt", count: 1, fps: 60) { i in
        AnyView(RingView(config: stage, diameter: 200, overrideElapsed: Double(i) / 60)
            .frame(width: 240, height: 240))
    }

    let smooth = config { $0.smoothingEnabled = true }
    timeFrames("stage ring, smoothed gradient", count: 1, fps: 60) { i in
        AnyView(RingView(config: smooth, diameter: 200, overrideElapsed: Double(i) / 60)
            .frame(width: 240, height: 240))
    }

    let diodes = config { $0.smoothingEnabled = true; $0.smoothingGradientRing = false }
    timeFrames("stage ring, smoothed diodes", count: 1, fps: 60) { i in
        AnyView(RingView(config: diodes, diameter: 200, overrideElapsed: Double(i) / 60)
            .frame(width: 240, height: 240))
    }

    // A real library pattern, not a Blender import.
    //
    // Everything above builds its config from spinning_rainbow.py, which
    // is a parametric animation — no recorded stream. The 78 patterns the
    // app actually ships are the other kind: a recorded command stream
    // replayed per frame, which is a completely different cost. Measuring
    // only the first kind is measuring the case nobody has on screen.
    let bundledConfig: RingConfig = {
        let c = RingConfig()
        if let preset = UseCaseLibrary.bundled?.presets.first(where: {
            $0.firmwarePatternStream != nil
        }) {
            preset.apply(to: c)
        }
        return c
    }()
    print("  (library pattern: stream = \(bundledConfig.firmwarePatternStream ?? "none"))")
    timeFrames("row 22pt, real library pattern", count: 1, fps: 12) { i in
        AnyView(RingView(config: bundledConfig, diameter: 22, overrideElapsed: Double(i) / 12,
                         frameRate: RingView.thumbnailFrameRate)
            .frame(width: 28, height: 28))
    }
    let bundledSmooth: RingConfig = {
        let c = RingConfig()
        if let preset = UseCaseLibrary.bundled?.presets.first(where: {
            $0.firmwarePatternStream != nil
        }) {
            preset.apply(to: c)
        }
        c.smoothingEnabled = true
        return c
    }()
    timeFrames("stage ring, real library pattern", count: 1, fps: 60) { i in
        AnyView(RingView(config: bundledSmooth, diameter: 200, overrideElapsed: Double(i) / 60)
            .frame(width: 240, height: 240))
    }

    // The worst case in the library: 3,359 recorded events, replayed from
    // the beginning on every sample.
    let heaviest: RingConfig = {
        let c = RingConfig()
        if let preset = UseCaseLibrary.bundled?.presets.first(where: {
            $0.firmwarePatternStream == "spinning_rainbow_quad"
        }) { preset.apply(to: c) }
        c.smoothingEnabled = true
        return c
    }()
    print("  (heaviest: stream = \(heaviest.firmwarePatternStream ?? "none"))")
    timeFrames("stage ring, heaviest pattern", count: 1, fps: 60) { i in
        AnyView(RingView(config: heaviest, diameter: 200, overrideElapsed: Double(i) / 60)
            .frame(width: 240, height: 240))
    }
    timeFrames("row 22pt, heaviest pattern", count: 20, fps: 12) { i in
        AnyView(RingView(config: heaviest, diameter: 22, overrideElapsed: Double(i) / 12,
                         frameRate: RingView.thumbnailFrameRate)
            .frame(width: 28, height: 28))
    }

    // The Cue Library's own rows, which nothing here had ever measured.
    // They render through `LEDCuePreviewView` rather than `RingView`, so
    // none of the numbers above describe them.
    if let cue = LEDCueLibrary.all.first {
        timeFrames("cue library row, 22pt", count: 20, fps: 12) { i in
            AnyView(LEDCuePreviewView(parameters: cue.defaultParameters, diameter: 22, lineWidth: 3,
                                      overrideElapsed: Double(i) / 12,
                                      frameRate: RingView.thumbnailFrameRate)
                .frame(width: 28, height: 28))
        }
    }
    // A ring whose config names a spec-sheet style: `RingView` hands it to
    // `LEDCuePreviewView`, rebuilding an `LEDCueParameters` every frame,
    // hex strings and all.
    let styled = config { $0.patternStyle = .spin; $0.firmwarePatternStream = nil }
    timeFrames("ring with a cue style, 200pt", count: 1, fps: 60) { i in
        AnyView(RingView(config: styled, diameter: 200, overrideElapsed: Double(i) / 60)
            .frame(width: 240, height: 240))
    }

    let thumb = config { _ in }
    timeFrames("one list row, 22pt", count: 1, fps: 12) { i in
        AnyView(RingView(config: thumb, diameter: 22, overrideElapsed: Double(i) / 12, frameRate: RingView.thumbnailFrameRate)
            .frame(width: 28, height: 28))
    }
    timeFrames("list rows visible in a sidebar", count: 20, fps: 12) { i in
        AnyView(RingView(config: thumb, diameter: 22, overrideElapsed: Double(i) / 12, frameRate: RingView.thumbnailFrameRate)
            .frame(width: 28, height: 28))
    }

    // What inside a 22pt thumbnail costs. The imported patterns are diode
    // mode plus a recorded stream, so a row is a full twenty-LED replay to
    // fill twenty-eight points.
    for count in [20.0, 8.0, 4.0] {
        let c = config { $0.diodeCount = count }
        timeFrames("row 22pt, \(Int(count)) diodes", count: 1, fps: 12) { i in
            AnyView(RingView(config: c, diameter: 22, overrideElapsed: Double(i) / 12, frameRate: RingView.thumbnailFrameRate)
                .frame(width: 28, height: 28))
        }
    }
    let plain = RingConfig()
    timeFrames("row 22pt, no diode mode at all", count: 1, fps: 12) { i in
        AnyView(RingView(config: plain, diameter: 22, overrideElapsed: Double(i) / 12)
            .frame(width: 28, height: 28))
    }
    let plainNoGlow = RingConfig()
    plainNoGlow.glowEnabled = false
    timeFrames("row 22pt, no diode mode, no glow", count: 1, fps: 12) { i in
        AnyView(RingView(config: plainNoGlow, diameter: 22, overrideElapsed: Double(i) / 12)
            .frame(width: 28, height: 28))
    }

    // Candidate: draw thumbnails through the smoothing pass's gradient ring
    // — one stroke instead of twenty positioned views — regardless of what
    // the config asks for.
    let gradientThumb = config { $0.smoothingEnabled = true; $0.smoothingGradientRing = true }
    timeFrames("row 22pt, gradient ring", count: 1, fps: 12) { i in
        AnyView(RingView(config: gradientThumb, diameter: 22, overrideElapsed: Double(i) / 12)
            .frame(width: 28, height: 28))
    }
    let gradientCheap = config {
        $0.smoothingEnabled = true
        $0.smoothingGradientRing = true
        $0.smoothingSpread = 0
        $0.smoothingTrail = 0
    }
    timeFrames("row 22pt, gradient, no smoothing taps", count: 1, fps: 12) { i in
        AnyView(RingView(config: gradientCheap, diameter: 22, overrideElapsed: Double(i) / 12)
            .frame(width: 28, height: 28))
    }

    let glowOff = config { $0.glowEnabled = false }
    timeFrames("stage ring, glow off", count: 1, fps: 60) { i in
        AnyView(RingView(config: glowOff, diameter: 200, overrideElapsed: Double(i) / 60)
            .frame(width: 240, height: 240))
    }

    let particles = config { $0.particlesEnabled = true }
    timeFrames("stage ring, particles on", count: 1, fps: 60) { i in
        AnyView(RingView(config: particles, diameter: 200, overrideElapsed: Double(i) / 60)
            .frame(width: 240, height: 240))
    }
    return 0
}
exit(run())
