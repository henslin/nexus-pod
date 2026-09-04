import Foundation
import SwiftUI

/// Generates standalone, drop-in source files (SwiftUI for iOS, Jetpack
/// Compose for Android, and vanilla HTML/Canvas for the web) that reproduce
/// whatever is currently configured in the app — same animation type,
/// speed, colors, easing curve, motion effects, everything.
public enum CodeGenerators {

    /// `swiftUICode`/`composeCode`/`webCode` below all switch exhaustively
    /// on `config.animationType` — they don't know about `config.patternStyle`
    /// (a Nexus feature added after these exporters existed) at all.
    /// Silently exporting `animationType`'s code while the live preview is
    /// actually showing a `patternStyle` override would be actively
    /// misleading (wrong animation, not just an incomplete one), so each of
    /// the three calls this first and bails out with an explanatory
    /// placeholder instead of guessing. Cue Library cues with a
    /// `LEDPatternStyle` already export correctly via `swiftUICueCode`/
    /// `composeCueCode`/`webCueCode` below — wiring Nexus's own
    /// exporters through the same path is a reasonable follow-up, just not
    /// done here.
    static func patternStyleExportPlaceholder(config: RingConfig) -> String? {
        guard let style = config.patternStyle, style != .continuousAnimation else { return nil }
        return """
        // This ring is currently set to the Pattern Style "\(style.displayName)"
        // (see the Animation section), which this exporter doesn't yet
        // translate into code — it only exports the continuous Animation
        // Type loop. To export code:
        //   1. Set Pattern Style back to "Continuous", or
        //   2. Recreate this look as a Cue Library cue with that same style
        //      and export it from there instead — the Cue Library's own
        //      exporter fully supports every Pattern Style.
        """
    }

    // MARK: - SwiftUI (iOS)

    /// Every color the ring uses, in the order the renderer cycles them —
    /// `primary`, `secondary`, then whatever else is configured. The same
    /// list `RingView.activeColors` builds, so an export can't disagree
    /// with the preview about how many colors there are.
    static func ringColorList(config: RingConfig) -> [String] {
        ([config.primaryColor, config.secondaryColor] + config.additionalColors)
            .map { $0.hexString }
    }

    public static func swiftUICode(config: RingConfig) -> String {
        if let placeholder = patternStyleExportPlaceholder(config: config) { return placeholder }
        let primaryHex = config.primaryColor.hexString
        let secondaryHex = config.secondaryColor.hexString
        let ringColorLiterals = ringColorList(config: config)
            .map { "Color(hex: \"\($0)\")" }
            .joined(separator: ", ")

        let animationBody: String
        switch config.animationType {
        case .wave:
            animationBody = """
Circle()
    .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
    .rotationEffect(.radians(phase))
"""
        case .chasing:
            animationBody = """
if chasingDrawUndraw {
    // Classic system-spinner move: the arc's start (from `.trim`'s 0) sits
    // at absolute angle `phase`, its end at `phase + length * 2π` — both
    // climb monotonically as `phase` does. Pulsing `length` with a sine
    // once per lap makes it grow from a point, then have its trailing edge
    // sweep forward to erase it — same clockwise direction throughout.
    let cycles = elapsed * speed
    let f = cycles - cycles.rounded(.down)
    let length = sin(f * Double.pi) * trailFraction
    ZStack {
        Circle()
            .stroke(p.opacity(0.12), lineWidth: lineWidth)
        Circle()
            .trim(from: 0, to: max(length, 0.0001))
            .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.radians(phase))
    }
} else {
    let head = phase / (2 * Double.pi)
    ZStack {
        Circle()
            .stroke(p.opacity(0.12), lineWidth: lineWidth)
        Circle()
            .trim(from: 0, to: trailFraction)
            .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.radians(head * 2 * Double.pi))
    }
}
"""
        case .alternating:
            animationBody = """
let blink = (sin(phase) + 1) / 2
GeometryReader { geo in
    let radius = min(geo.size.width, geo.size.height) / 2 - lineWidth / 2
    ZStack {
        ForEach(0..<diodeCount, id: \\.self) { i in
            let angle = (Double(i) / Double(diodeCount)) * 2 * Double.pi - .pi / 2
            let isEven = i.isMultiple(of: 2)
            Circle()
                .fill(isEven ? p : s)
                .frame(width: lineWidth, height: lineWidth)
                .opacity(isEven ? blink : 1 - blink)
                .position(
                    x: geo.size.width / 2 + cos(angle) * radius,
                    y: geo.size.height / 2 + sin(angle) * radius
                )
        }
    }
    .frame(width: geo.size.width, height: geo.size.height)
}
"""
        case .multiChase:
            // Every configured color gets its own comet, as in the app.
            // This used to emit two, on the reasoning that a color array
            // would have to come from the host app — but the array can just
            // be a literal (see `ringColors`), so the file stays a drop-in
            // and stops disagreeing with the preview.
            animationBody = """
let head = phase / (2 * Double.pi)
let tail = max(trailFraction, 0.02)
let all = activeColors(elapsed: elapsed)
GeometryReader { geo in
    let radius = min(geo.size.width, geo.size.height) / 2 - lineWidth / 2
    ZStack {
        ForEach(0..<diodeCount, id: \\.self) { i in
            let position = Double(i) / Double(diodeCount)
            let lit = brightestComet(at: position, head: head, tail: tail, colorCount: all.count)
            let angle = position * 2 * Double.pi - .pi / 2
            Circle()
                .fill(all[lit.index % max(all.count, 1)])
                .frame(width: lineWidth, height: lineWidth)
                .opacity(max(lit.brightness, 0.06))
                .position(
                    x: geo.size.width / 2 + cos(angle) * radius,
                    y: geo.size.height / 2 + sin(angle) * radius
                )
        }
    }
    .frame(width: geo.size.width, height: geo.size.height)
}
"""
        case .bloom:
            // Same seeded field as the app (`RingView.blooms`): widths,
            // centers and swell rates all derived from `pseudoRandom` so
            // the generated file reproduces identical frames.
            animationBody = """
let bloomCount = 6
ZStack {
    Circle()
        .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        .opacity(bloomBase)
    ForEach(0..<bloomCount, id: \\.self) { i in
        let rateSeed = pseudoRandom(i + 211)
        let period = max(6.0 / max(speed, 0.05) * (0.55 + rateSeed), 0.3)
        let local = elapsed / period
        let cycle = Int(local.rounded(.down))
        let f = local - Double(cycle)
        let placeSeed = pseudoRandom2(i, cycle)
        let peakSeed = pseudoRandom2(i, cycle + 4096)
        let driftSeed = pseudoRandom2(i, cycle + 8192)
        let envelope = sin(f * .pi)
        let length = max(trailFraction, 0.02) * (0.33 + peakSeed * 0.67) * envelope
        let center = placeSeed + (driftSeed - 0.5) * 0.15 * f
        let intensity = pow(envelope, 1.4) * (0.55 + peakSeed * 0.45)
        let drawn = max(length, 0.0005)
        Circle()
            .trim(from: center - drawn / 2, to: center + drawn / 2)
            .stroke(i.isMultiple(of: 2) ? p : s,
                    style: StrokeStyle(lineWidth: lineWidth * CGFloat(0.75 + intensity * 0.5), lineCap: .round))
            .rotationEffect(.degrees(-90))
            .opacity(intensity)
            .blur(radius: lineWidth * bloomSoftness)
            .blendMode(.plusLighter)
    }
}
"""
        case .pulse:
            animationBody = """
let value = (sin(phase) + 1) / 2
Circle()
    .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth * (0.7 + 0.6 * value), lineCap: .round))
    .opacity(0.55 + 0.45 * value)
    .scaleEffect(0.94 + 0.06 * value)
"""
        case .ripple:
            animationBody = """
let cycles = elapsed * speed
let f = cycles - cycles.rounded(.down)
let waveCount = 3
ZStack {
    Circle()
        .stroke(p.opacity(0.25), lineWidth: lineWidth)
    ForEach(0..<waveCount, id: \\.self) { i in
        let localT = (f + Double(i) / Double(waveCount)).truncatingRemainder(dividingBy: 1)
        Circle()
            .stroke(
                (i.isMultiple(of: 2) ? p : s).opacity((1 - localT) * 0.8),
                lineWidth: lineWidth * CGFloat(1 - localT * 0.5)
            )
            .scaleEffect(1 + localT * 0.6)
    }
}
"""
        case .wobble:
            animationBody = """
GeometryReader { geo in
    let size = min(geo.size.width, geo.size.height)
    let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
    let baseRadius = size / 2 - lineWidth / 2
    let amplitude = size * 0.035
    Path { path in
        let steps = 120
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let theta = t * 2 * Double.pi
            let wobble = sin(theta * 3 + phase) + sin(theta * 5 - phase * 1.3) * 0.5
            let radius = baseRadius + amplitude * CGFloat(wobble) / 1.5
            let x = center.x + CGFloat(cos(theta)) * radius
            let y = center.y + CGFloat(sin(theta)) * radius
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()
    }
    .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
}
"""
        case .equalizer:
            animationBody = """
let count = max(diodeCount, 4)
let segmentFraction = (1.0 / Double(count)) * 0.7
ZStack {
    Circle().stroke(p.opacity(0.12), lineWidth: lineWidth)
    ForEach(0..<count, id: \\.self) { i in
        let seed = pseudoRandom(i)
        let localPhase = elapsed * speed * 2 * Double.pi * (0.6 + seed * 0.8) + seed * 2 * Double.pi
        let value = min((sin(localPhase) + 1) / 2, 1)
        let start = Double(i) / Double(count)
        Circle()
            .trim(from: start, to: start + segmentFraction)
            .stroke(
                i.isMultiple(of: 2) ? p : s,
                style: StrokeStyle(lineWidth: lineWidth * CGFloat(0.3 + value * 0.7), lineCap: .round)
            )
            .opacity(0.5 + value * 0.5)
    }
}
"""
        case .dualChase:
            animationBody = """
ZStack {
    Circle()
        .stroke(p.opacity(0.12), lineWidth: lineWidth)
    Circle()
        .trim(from: 0, to: trailFraction)
        .stroke(p, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        .rotationEffect(.radians(phase))
    Circle()
        .trim(from: 0, to: trailFraction)
        .stroke(s, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        .rotationEffect(.radians(-phase))
}
"""
        case .sparkle:
            animationBody = """
GeometryReader { geo in
    let radius = min(geo.size.width, geo.size.height) / 2 - lineWidth / 2
    ZStack {
        Circle().stroke(p.opacity(0.1), lineWidth: lineWidth * 0.4)
        ForEach(0..<diodeCount, id: \\.self) { i in
            let angle = (Double(i) / Double(diodeCount)) * 2 * Double.pi - .pi / 2
            let seed = pseudoRandom(i)
            let cycles = elapsed * speed * (0.5 + seed) + seed * 4
            let f = cycles - cycles.rounded(.down)
            let brightness = max(0, 1 - f * 4)
            Circle()
                .fill(i.isMultiple(of: 2) ? p : s)
                .frame(width: lineWidth, height: lineWidth)
                .opacity(0.15 + brightness * 0.85)
                .scaleEffect(0.6 + brightness * 0.6)
                .position(
                    x: geo.size.width / 2 + cos(angle) * radius,
                    y: geo.size.height / 2 + sin(angle) * radius
                )
        }
    }
    .frame(width: geo.size.width, height: geo.size.height)
}
"""
        case .aurora:
            animationBody = """
let bandCount = 3
ZStack {
    Circle().stroke(p.opacity(0.08), lineWidth: lineWidth * 0.4)
    ForEach(0..<bandCount, id: \\.self) { i in
        let seed = pseudoRandom(i)
        let bandSpeed = speed * (0.12 + seed * 0.22)
        let bandPhase = elapsed * bandSpeed * 2 * Double.pi + seed * 2 * Double.pi
        let bandLength = 0.22 + seed * 0.16
        let pulse = 0.5 + 0.5 * sin(elapsed * (0.3 + seed * 0.4) + seed * 6)
        Circle()
            .trim(from: 0, to: bandLength)
            .stroke(
                i.isMultiple(of: 2) ? p : s,
                style: StrokeStyle(lineWidth: lineWidth * 1.5, lineCap: .round)
            )
            .rotationEffect(.radians(bandPhase))
            .opacity(min(0.25 + 0.45 * pulse, 1))
            .blur(radius: lineWidth * 0.4)
    }
}
"""
        case .liquidFill:
            animationBody = """
let riseCycles = elapsed * speed * 0.35
let levelBase = (sin(riseCycles * 2 * Double.pi) + 1) / 2
let slosh = sin(elapsed * speed * 2 * Double.pi * 1.8) * 0.04
let level = min(max(levelBase + slosh, 0.02), 0.98)
ZStack {
    Circle()
        .stroke(p.opacity(0.12), lineWidth: lineWidth)
    Circle()
        .trim(from: 0, to: level)
        .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        .rotationEffect(.radians(.pi / 2))
    Circle()
        .trim(from: max(level - 0.015, 0), to: level)
        .stroke(s, style: StrokeStyle(lineWidth: lineWidth * 1.3, lineCap: .round))
        .rotationEffect(.radians(.pi / 2))
}
"""
        }

        let header = """
// Generated by RingAnimator
// Animation: \(config.animationType.rawValue) · Easing: \(config.easingStyle.rawValue)
//
// Drop this file into your iOS app. Place `ThinkingRingView()` wherever
// the ring lives in your tab bar (e.g. as a custom tab item view).
// Self-contained — no dependencies beyond SwiftUI.

import SwiftUI

struct ThinkingRingView: View {
    var diameter: CGFloat = \(Int(config.previewDiameter))
    var lineWidth: CGFloat = \(config.lineWidth)
    var speed: Double = \(config.speed) // cycles per second
    var trailFraction: Double = \(config.trailFraction)
    var bloomBase: Double = \(config.bloomBase)
    var bloomSoftness: Double = \(config.bloomSoftness)
    var chasingDrawUndraw: Bool = \(config.chasingFillStyle == .drawUndraw)
    var diodeCount: Int = \(Int(config.diodeCount.rounded()))
    // Diode Mode — the pixels are fixed and an animation is a brightness
    // pattern swept across them. See `diodeState` below.
    var diodeScale: CGFloat = \(config.diodeScale)
    var diodeGap: Double = \(config.diodeGap)
    var diodeFloor: Double = \(config.diodeFloor)
    var loopSeconds: Double = \(config.loopSeconds)
    var rippleDropCount: Double = \(config.rippleDropCount)
    var rippleDecay: Double = \(config.rippleDecay)
    var rippleLife: Double = \(config.rippleLife)
    var rippleSeed: Double = \(config.rippleSeed)
    var bloomCount: Double = \(config.bloomCount)
    var primaryColor: Color = Color(hex: "\(primaryHex)")
    var secondaryColor: Color = Color(hex: "\(secondaryHex)")
    // Every configured color, in order. The app cycles all of them — Multi
    // Chase gives each its own comet, and hue shift rotates through the
    // whole list — so exporting only primary and secondary quietly dropped
    // however many you'd added. Emitted as literals rather than taken as a
    // parameter so the file stays a drop-in.
    var ringColors: [Color] = [\(ringColorLiterals)]
    var glowEnabled: Bool = \(config.glowEnabled)
    var glowRadius: CGFloat = \(config.glowRadius)

    // Motion effects
    var easing: Easing = .\(swiftEasingCaseName(config.easingStyle))
    var springBounce: Double = \(config.springBounce)
    var scalePulseEnabled: Bool = \(config.scalePulseEnabled)
    var scalePulseAmount: Double = \(config.scalePulseAmount)
    var scalePulseSpeed: Double = \(config.scalePulseSpeed)
    var hueShiftEnabled: Bool = \(config.hueShiftEnabled)
    var hueShiftSpeed: Double = \(config.hueShiftSpeed)
    var blurRadius: CGFloat = \(config.blurRadius)
    var blendMode: BlendMode = .\(swiftBlendModeCaseName(config.blendMode))
    // Deliberately exaggerated RGB split — see `aberratedRing`.
    var chromaticAberrationEnabled: Bool = \(config.chromaticAberrationEnabled)
    var chromaticAberrationAmount: CGFloat = \(config.chromaticAberrationAmount)

    // Particles — literal CAEmitterLayer/CAEmitterCell parameters,
    // reproduced here with plain SwiftUI math since a drop-in file can't
    // depend on RingAnimatorCore's real Core Animation emitter. `emitterShape`
    // and `renderMode` are carried through as plain values for reference —
    // this hand-written approximation always lays particles out on a circle
    // matching the ring, the same way the shape/mode combination the app
    // defaults to (Circle + Outline) would render for real.
    var particlesEnabled: Bool = \(config.particlesEnabled)
    var particleEmitterShape: String = "\(config.particleEmitterShape.rawValue)"
    var particleEmitterMode: ParticleEmitterMode = .\(swiftEmitterModeCaseName(config.particleEmitterMode))
    var particleEmitterSizeMultiplier: Double = \(config.particleEmitterSizeMultiplier)
    var particleRenderMode: String = "\(config.particleRenderMode.rawValue)"
    var particleBirthRate: Double = \(config.particleBirthRate)
    var particleLifetime: Double = \(config.particleLifetime)
    var particleLifetimeRange: Double = \(config.particleLifetimeRange)
    var particleVelocity: Double = \(config.particleVelocity)
    var particleVelocityRange: Double = \(config.particleVelocityRange)
    var particleEmissionLongitude: Double = \(config.particleEmissionLongitude)
    var particleEmissionSpread: Double = \(config.particleEmissionSpread)
    var particleXAcceleration: Double = \(config.particleXAcceleration)
    var particleYAcceleration: Double = \(config.particleYAcceleration)
    var particleSpin: Double = \(config.particleSpin)
    var particleSpinRange: Double = \(config.particleSpinRange)
    var particleScale: CGFloat = \(config.particleScale)
    var particleScaleRange: CGFloat = \(config.particleScaleRange)
    var particlePulseEnabled: Bool = \(config.particlePulseEnabled)
    var particlePulsePeriod: Double = \(config.particlePulsePeriod)
    var particleBlurRadius: CGFloat = \(config.particleBlurRadius)

    enum Easing {
        case linear, easeIn, easeOut, easeInOut, spring
    }

    // Mirrors CAEmitterLayer.emitterMode — .points/.outline place particles
    // exactly on the emitter circle's edge; .surface/.volume scatter them
    // anywhere inside it.
    enum ParticleEmitterMode {
        case points, outline, surface, volume
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            let phase = easedPhase(elapsed: elapsed)
            let breathing = scalePulseEnabled
                ? 1 + scalePulseAmount * sin(elapsed * scalePulseSpeed * 2 * .pi)
                : 1
            let (glowColor, _) = colors(elapsed: elapsed)

            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height, diameter)
                ZStack {
                    aberratedRing(phase: phase, elapsed: elapsed)
                        .frame(width: size, height: size)
                    if particlesEnabled {
                        particles(elapsed: elapsed, size: size)
                            .frame(width: size, height: size)
                    }
                }
                .scaleEffect(breathing)
                .blur(radius: blurRadius)
                .shadow(color: glowEnabled ? glowColor.opacity(0.7) : .clear,
                        radius: glowEnabled ? glowRadius : 0)
                .compositingGroup()
                .blendMode(blendMode)
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }

    // Per-cycle easing keeps rotation perfectly continuous — see the
    // RingAnimator README for why this never causes a visible snap.
    private func easedPhase(elapsed: Double) -> Double {
        let cycles = elapsed * speed
        let n = cycles.rounded(.down)
        let f = cycles - n
        return (n + applyEasing(f)) * 2 * Double.pi
    }

    private func applyEasing(_ t: Double) -> Double {
        switch easing {
        case .linear: return t
        case .easeIn: return t * t
        case .easeOut: return 1 - (1 - t) * (1 - t)
        case .easeInOut: return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        case .spring:
            let decay = exp(-6 * t)
            return t + springBounce * decay * sin(t * .pi * 6)
        }
    }

    /// Every color the ring is currently using, hue shift applied.
    private func activeColors(elapsed: Double) -> [Color] {
        guard hueShiftEnabled else { return ringColors }
        let raw = (elapsed * hueShiftSpeed).truncatingRemainder(dividingBy: 1)
        let base = raw < 0 ? raw + 1 : raw
        let n = max(ringColors.count, 1)
        return (0..<n).map { i in
            let hue = (base + Double(i) / Double(n)).truncatingRemainder(dividingBy: 1)
            return Color(hue: hue, saturation: 0.85, brightness: 1)
        }
    }

    /// The two-color view of the above, for the animations that only ever
    /// use a pair. With two colors and hue shift on, the spacing works out
    /// to the same half-turn apart this used to hard-code.
    private func colors(elapsed: Double) -> (Color, Color) {
        let all = activeColors(elapsed: elapsed)
        guard let first = all.first else { return (primaryColor, secondaryColor) }
        return (first, all.count > 1 ? all[1] : first)
    }

    // Deterministic pseudo-random value in 0..<1 for a given index — used
    // by Equalizer/Sparkle so each segment/point gets its own scattered-
    // looking but fully reproducible rate and phase offset.
    private func pseudoRandom(_ i: Int) -> Double {
        let x = sin(Double(i) * 12.9898) * 43758.5453
        return x - x.rounded(.down)
    }

    /// Two-input hash — Bloom rerolls a patch's position and size on every
    /// surfacing, so its seed depends on which surfacing this is, not just
    /// which patch.
    private func pseudoRandom2(_ a: Int, _ b: Int) -> Double {
        let x = sin(Double(a) * 12.9898 + Double(b) * 78.233) * 43758.5453
        return x - x.rounded(.down)
    }

    /// Which of Multi Chase's two comets is brightest at a point on the
    /// ring, and how bright.
    ///
    /// A function rather than inline in the view body because a
    /// `@ViewBuilder` closure accepts `let` bindings and view expressions
    /// only — `var` and `for` inside one make the builder try to treat
    /// them as views.
    private func brightestComet(
        at position: Double,
        head: Double,
        tail: Double,
        colorCount: Int
    ) -> (index: Int, brightness: Double) {
        var bestIndex = 0
        var bestBrightness = 0.0
        let count = max(colorCount, 1)
        for k in 0..<count {
            let cometHead = head + Double(k) / Double(count)
            // Distance *behind* the comet head, wrapped into 0..<1 so the
            // comparison works across the seam at the top of the ring.
            var behind = (cometHead - position).truncatingRemainder(dividingBy: 1)
            if behind < 0 { behind += 1 }
            if behind < tail {
                let brightness = 1 - (behind / tail)
                if brightness > bestBrightness {
                    bestBrightness = brightness
                    bestIndex = k
                }
            }
        }
        // Unlit diodes stay faintly visible, the same way `chasing` draws a
        // dim full-circle track behind its arc — otherwise the ring's shape
        // disappears wherever no comet currently is.
        return bestBrightness > 0.06 ? (bestIndex, bestBrightness) : (bestIndex, 0.06)
    }

    // Deliberately exaggerated RGB split, inspired by Siri's colorful
    // "wavelengths" — three color-isolated (`.colorMultiply` zeroes out the
    // other two channels), offset, screen-blended copies of the same ring.
    // Universal: doesn't touch `ring(phase:elapsed:)` itself.
    @ViewBuilder
    private func aberratedRing(phase: Double, elapsed: Double) -> some View {
        if chromaticAberrationEnabled {
            ZStack {
                ring(phase: phase, elapsed: elapsed)
                    .colorMultiply(.red)
                    .blendMode(.screen)
                    .offset(x: -chromaticAberrationAmount, y: chromaticAberrationAmount * 0.3)
                ring(phase: phase, elapsed: elapsed)
                    .colorMultiply(.green)
                    .blendMode(.screen)
                    .offset(x: 0, y: -chromaticAberrationAmount * 0.5)
                ring(phase: phase, elapsed: elapsed)
                    .colorMultiply(.blue)
                    .blendMode(.screen)
                    .offset(x: chromaticAberrationAmount, y: chromaticAberrationAmount * 0.3)
            }
            .compositingGroup()
        } else {
            ring(phase: phase, elapsed: elapsed)
        }
    }

    @ViewBuilder
    private func ring(phase: Double, elapsed: Double) -> some View {
        let (p, s) = colors(elapsed: elapsed)
        let gradient = AngularGradient(colors: [p, s, p], center: .center)
"""

        let particlesFunc = swiftParticlesFunc()

        let footer = """
}

// MARK: - Hex color helper
extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")))
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
"""

        // Diode Mode replaces the animation body outright rather than
        // layering on top of it: the continuous renderers draw arcs that
        // rotate and gradients that sweep, and this draws fixed pixels
        // whose brightness changes. There is nothing to share.
        let body = config.diodeModeEnabled ? swiftDiodeBody() : animationBody
        let diodeSupport = config.diodeModeEnabled ? swiftDiodeSupport(config: config) : ""
        return header + "\n" + indent(body, by: 8) + "\n    }\n"
            + particlesFunc + diodeSupport + "\n" + footer
    }

    // MARK: - Jetpack Compose (Android)

    public static func composeCode(config: RingConfig) -> String {
        if let placeholder = patternStyleExportPlaceholder(config: config) { return placeholder }
        let primaryHex = config.primaryColor.hexString.replacingOccurrences(of: "#", with: "")
        let secondaryHex = config.secondaryColor.hexString.replacingOccurrences(of: "#", with: "")

        let animationBody: String
        switch config.animationType {
        case .wave:
            animationBody = """
rotate(degrees = Math.toDegrees(phase).toFloat()) {
    drawArc(
        brush = sweepBrush(center, p, s),
        startAngle = 0f,
        sweepAngle = 360f,
        useCenter = false,
        style = Stroke(width = lineWidthPx, cap = StrokeCap.Round),
        blendMode = blendMode
    )
}
"""
        case .chasing:
            animationBody = """
drawArc(
    color = p.copy(alpha = 0.12f),
    startAngle = 0f,
    sweepAngle = 360f,
    useCenter = false,
    style = Stroke(width = lineWidthPx)
)
if (chasingDrawUndraw) {
    // Classic system-spinner move: startAngle sits at `phase` (climbing
    // monotonically), sweepAngle pulses 0 -> trailFraction -> 0 once per
    // lap via a sine, so the arc grows from a point then has its trailing
    // edge sweep forward to erase it — same clockwise direction throughout.
    val cycles = elapsedSeconds * speed
    val n = floor(cycles)
    val f = (cycles - n).toFloat()
    val length = (sin((f * Math.PI).toFloat()) * trailFraction.toFloat()).coerceAtLeast(0.0001f)
    drawArc(
        brush = sweepBrush(center, p, s),
        startAngle = Math.toDegrees(phase).toFloat(),
        sweepAngle = 360f * length,
        useCenter = false,
        style = Stroke(width = lineWidthPx, cap = StrokeCap.Round),
        blendMode = blendMode
    )
} else {
    val headDegrees = Math.toDegrees(phase).toFloat()
    rotate(degrees = headDegrees) {
        drawArc(
            brush = sweepBrush(center, p, s),
            startAngle = 0f,
            sweepAngle = 360f * trailFraction.toFloat(),
            useCenter = false,
            style = Stroke(width = lineWidthPx, cap = StrokeCap.Round),
            blendMode = blendMode
        )
    }
}
"""
        case .alternating:
            animationBody = """
val blink = ((sin(phase) + 1) / 2).toFloat()
val dotRadius = lineWidthPx / 2f
val ringRadius = (size.minDimension / 2f) - dotRadius
for (i in 0 until diodeCount) {
    val angle = (i.toDouble() / diodeCount) * 2 * Math.PI - Math.PI / 2
    val isEven = i % 2 == 0
    val dotColor = if (isEven) p else s
    val dotAlpha = if (isEven) blink else 1f - blink
    val x = center.x + (cos(angle) * ringRadius).toFloat()
    val y = center.y + (sin(angle) * ringRadius).toFloat()
    drawCircle(
        color = dotColor.copy(alpha = dotAlpha),
        radius = dotRadius,
        center = Offset(x, y),
        blendMode = blendMode
    )
}
"""
        case .multiChase:
            animationBody = """
val head = phase / (2 * Math.PI)
val tail = maxOf(trailFraction, 0.02)
val dotRadius = lineWidthPx / 2f
val ringRadius = (size.minDimension / 2f) - dotRadius
for (i in 0 until diodeCount) {
    val position = i.toDouble() / diodeCount
    var bestIndex = 0
    var bestBrightness = 0.0
    for (k in 0 until 2) {
        val cometHead = head + k / 2.0
        var behind = (cometHead - position) % 1.0
        if (behind < 0) behind += 1.0
        if (behind < tail) {
            val brightness = 1.0 - (behind / tail)
            if (brightness > bestBrightness) { bestBrightness = brightness; bestIndex = k }
        }
    }
    val angle = position * 2 * Math.PI - Math.PI / 2
    val dotColor = if (bestIndex == 0) p else s
    drawCircle(
        color = dotColor.copy(alpha = maxOf(bestBrightness, 0.06).toFloat()),
        radius = dotRadius,
        center = Offset(
            (size.width / 2f) + (cos(angle) * ringRadius).toFloat(),
            (size.height / 2f) + (sin(angle) * ringRadius).toFloat()
        )
    )
}
"""
        case .bloom:
            animationBody = """
val bloomCount = 6
drawCircle(
    brush = Brush.sweepGradient(listOf(p, s, p)),
    radius = radiusPx,
    alpha = bloomBase.toFloat(),
    style = Stroke(width = lineWidthPx)
)
for (i in 0 until bloomCount) {
    val rateSeed = pseudoRandom(i + 211)
    val period = maxOf(6.0 / maxOf(speed, 0.05) * (0.55 + rateSeed), 0.3)
    val local = elapsedSeconds / period
    val cycle = Math.floor(local).toInt()
    val f = local - cycle
    val placeSeed = pseudoRandom2(i, cycle)
    val peakSeed = pseudoRandom2(i, cycle + 4096)
    val driftSeed = pseudoRandom2(i, cycle + 8192)
    val envelope = sin(f * PI)
    val length = maxOf(maxOf(trailFraction, 0.02) * (0.33 + peakSeed * 0.67) * envelope, 0.0005)
    val center = placeSeed + (driftSeed - 0.5) * 0.15 * f
    val intensity = Math.pow(envelope, 1.4) * (0.55 + peakSeed * 0.45)
    // Compose's Canvas has no per-draw blur, so `bloomSoftness` is not
    // applied here — the patches are crisp. Wrap the Canvas in a
    // `graphicsLayer { renderEffect = BlurEffect(...) }` if you want it.
    drawArc(
        color = (if (i % 2 == 0) p else s).copy(alpha = intensity.toFloat()),
        startAngle = ((center - length / 2) * 360.0 - 90.0).toFloat(),
        sweepAngle = (length * 360.0).toFloat(),
        useCenter = false,
        style = Stroke(width = (lineWidthPx * (0.75 + intensity * 0.5)).toFloat(), cap = StrokeCap.Round)
    )
}
"""
        case .pulse:
            animationBody = """
val value = (sin(phase) + 1) / 2
val width = (lineWidthPx * (0.7f + 0.6f * value)).toFloat()
val alpha = (0.55f + 0.45f * value).toFloat()
drawArc(
    brush = sweepBrush(center, p, s),
    startAngle = 0f,
    sweepAngle = 360f,
    useCenter = false,
    style = Stroke(width = width, cap = StrokeCap.Round),
    alpha = alpha,
    blendMode = blendMode
)
"""
        case .ripple:
            animationBody = """
val cycles = elapsedSeconds * speed
val n = floor(cycles)
val f = (cycles - n).toFloat()
val waveCount = 3
drawCircle(
    color = p.copy(alpha = 0.25f),
    radius = size.minDimension / 2f,
    center = center,
    style = Stroke(width = lineWidthPx)
)
for (i in 0 until waveCount) {
    val localT = (f + i.toFloat() / waveCount) % 1f
    val waveColor = if (i % 2 == 0) p else s
    drawCircle(
        color = waveColor.copy(alpha = (1f - localT) * 0.8f),
        radius = (size.minDimension / 2f) * (1f + localT * 0.6f),
        center = center,
        style = Stroke(width = lineWidthPx * (1f - localT * 0.5f))
    )
}
"""
        case .wobble:
            animationBody = """
val baseRadius = size.minDimension / 2f - lineWidthPx / 2f
val amplitude = size.minDimension * 0.035f
val path = Path()
val steps = 120
for (i in 0..steps) {
    val t = i.toDouble() / steps
    val theta = t * 2 * Math.PI
    val wobble = sin(theta * 3 + phase) + sin(theta * 5 - phase * 1.3) * 0.5
    val radius = baseRadius + amplitude * (wobble / 1.5).toFloat()
    val x = center.x + (cos(theta) * radius).toFloat()
    val y = center.y + (sin(theta) * radius).toFloat()
    if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
}
path.close()
drawPath(
    path = path,
    brush = sweepBrush(center, p, s),
    style = Stroke(width = lineWidthPx, cap = StrokeCap.Round, join = StrokeJoin.Round)
)
"""
        case .equalizer:
            animationBody = """
val count = diodeCount.coerceAtLeast(4)
val segmentSweep = (360f / count) * 0.7f
drawArc(
    color = p.copy(alpha = 0.12f),
    startAngle = 0f,
    sweepAngle = 360f,
    useCenter = false,
    style = Stroke(width = lineWidthPx)
)
for (i in 0 until count) {
    val seed = pseudoRandom(i)
    val localPhase = elapsedSeconds * speed * 2 * Math.PI * (0.6 + seed * 0.8) + seed * 2 * Math.PI
    val value = (((sin(localPhase) + 1) / 2)).coerceAtMost(1.0).toFloat()
    val startAngle = (i.toFloat() / count) * 360f
    val segColor = if (i % 2 == 0) p else s
    drawArc(
        color = segColor,
        startAngle = startAngle,
        sweepAngle = segmentSweep,
        useCenter = false,
        style = Stroke(width = lineWidthPx * (0.3f + value * 0.7f), cap = StrokeCap.Round),
        alpha = 0.5f + value * 0.5f,
        blendMode = blendMode
    )
}
"""
        case .dualChase:
            animationBody = """
drawArc(
    color = p.copy(alpha = 0.12f),
    startAngle = 0f,
    sweepAngle = 360f,
    useCenter = false,
    style = Stroke(width = lineWidthPx)
)
val headDegrees = Math.toDegrees(phase).toFloat()
drawArc(
    color = p,
    startAngle = headDegrees,
    sweepAngle = 360f * trailFraction.toFloat(),
    useCenter = false,
    style = Stroke(width = lineWidthPx, cap = StrokeCap.Round),
    blendMode = blendMode
)
drawArc(
    color = s,
    startAngle = -headDegrees,
    sweepAngle = 360f * trailFraction.toFloat(),
    useCenter = false,
    style = Stroke(width = lineWidthPx, cap = StrokeCap.Round),
    blendMode = blendMode
)
"""
        case .sparkle:
            animationBody = """
val dotRadius = lineWidthPx / 2f
val ringRadius = (size.minDimension / 2f) - dotRadius
drawCircle(
    color = p.copy(alpha = 0.1f),
    radius = size.minDimension / 2f,
    center = center,
    style = Stroke(width = lineWidthPx * 0.4f)
)
for (i in 0 until diodeCount) {
    val angle = (i.toDouble() / diodeCount) * 2 * Math.PI - Math.PI / 2
    val seed = pseudoRandom(i)
    val cycles = elapsedSeconds * speed * (0.5 + seed) + seed * 4
    val n = floor(cycles)
    val f = cycles - n
    val brightness = (1 - f * 4).coerceAtLeast(0.0)
    val dotColor = if (i % 2 == 0) p else s
    val x = center.x + (cos(angle) * ringRadius).toFloat()
    val y = center.y + (sin(angle) * ringRadius).toFloat()
    drawCircle(
        color = dotColor.copy(alpha = (0.15 + brightness * 0.85).toFloat()),
        radius = dotRadius * (0.6f + (brightness * 0.6).toFloat()),
        center = Offset(x, y),
        blendMode = blendMode
    )
}
"""
        case .aurora:
            animationBody = """
val bandCount = 3
drawArc(
    color = p.copy(alpha = 0.08f),
    startAngle = 0f,
    sweepAngle = 360f,
    useCenter = false,
    style = Stroke(width = lineWidthPx * 0.4f)
)
for (i in 0 until bandCount) {
    val seed = pseudoRandom(i)
    val bandSpeed = speed * (0.12 + seed * 0.22)
    val bandPhaseDeg = Math.toDegrees(elapsedSeconds * bandSpeed * 2 * Math.PI + seed * 2 * Math.PI).toFloat()
    val bandLength = (0.22 + seed * 0.16)
    val pulse = 0.5 + 0.5 * sin(elapsedSeconds * (0.3 + seed * 0.4) + seed * 6)
    val bandColor = if (i % 2 == 0) p else s
    drawArc(
        color = bandColor.copy(alpha = minOf(0.25f + 0.45f * pulse.toFloat(), 1f)),
        startAngle = bandPhaseDeg,
        sweepAngle = (360.0 * bandLength).toFloat(),
        useCenter = false,
        style = Stroke(width = lineWidthPx * 1.5f, cap = StrokeCap.Round),
        blendMode = blendMode
    )
}
"""
        case .liquidFill:
            animationBody = """
val riseCycles = elapsedSeconds * speed * 0.35
val levelBase = (sin(riseCycles * 2 * Math.PI) + 1) / 2
val slosh = sin(elapsedSeconds * speed * 2 * Math.PI * 1.8) * 0.04
val level = (levelBase + slosh).coerceIn(0.02, 0.98)
drawArc(
    color = p.copy(alpha = 0.12f),
    startAngle = 0f,
    sweepAngle = 360f,
    useCenter = false,
    style = Stroke(width = lineWidthPx)
)
drawArc(
    brush = sweepBrush(center, p, s),
    startAngle = 90f,
    sweepAngle = (360.0 * level).toFloat(),
    useCenter = false,
    style = Stroke(width = lineWidthPx, cap = StrokeCap.Round),
    blendMode = blendMode
)
val capStart = 90.0 + 360.0 * maxOf(level - 0.015, 0.0)
drawArc(
    color = s,
    startAngle = capStart.toFloat(),
    sweepAngle = (360.0 * 0.015).toFloat(),
    useCenter = false,
    style = Stroke(width = lineWidthPx * 1.3f, cap = StrokeCap.Round),
    blendMode = blendMode
)
"""
        }

        let header = """
// Generated by RingAnimator
// Animation: \(config.animationType.rawValue) · Easing: \(config.easingStyle.rawValue)
//
// Drop this file into your Android app. Place `ThinkingRingView()` in
// your bottom navigation / tab bar composable.

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.unit.dp
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin

private val PrimaryColor = Color(0xFF\(primaryHex))
private val SecondaryColor = Color(0xFF\(secondaryHex))

enum class RingEasing { LINEAR, EASE_IN, EASE_OUT, EASE_IN_OUT, SPRING }

private fun applyEasing(t: Double, easing: RingEasing, bounce: Double): Double = when (easing) {
    RingEasing.LINEAR -> t
    RingEasing.EASE_IN -> t * t
    RingEasing.EASE_OUT -> 1 - (1 - t) * (1 - t)
    RingEasing.EASE_IN_OUT -> if (t < 0.5) 2 * t * t else 1 - (-2 * t + 2).pow(2) / 2
    RingEasing.SPRING -> {
        val decay = exp(-6 * t)
        t + bounce * decay * sin(t * Math.PI * 6)
    }
}

// Deterministic pseudo-random value in 0..<1 for a given index — used by
// Equalizer/Sparkle so each segment/point gets its own scattered-looking
// but fully reproducible rate and phase offset.
private fun pseudoRandom(i: Int): Double {
    val x = sin(i.toDouble() * 12.9898) * 43758.5453
    return x - floor(x)
}

// Two-input hash — Bloom rerolls a patch's position and size on every
// surfacing, so its seed depends on which surfacing this is.
private fun pseudoRandom2(a: Int, b: Int): Double {
    val x = sin(a.toDouble() * 12.9898 + b.toDouble() * 78.233) * 43758.5453
    return x - floor(x)
}

@Composable
fun ThinkingRingView(
    modifier: Modifier = Modifier,
    diameterDp: Int = \(Int(config.previewDiameter)),
    lineWidthDp: Float = \(config.lineWidth)f,
    speed: Double = \(config.speed), // cycles per second
    trailFraction: Double = \(config.trailFraction),
    bloomBase: Double = \(config.bloomBase),
    bloomSoftness: Double = \(config.bloomSoftness),
    chasingDrawUndraw: Boolean = \(config.chasingFillStyle == .drawUndraw),
    diodeCount: Int = \(Int(config.diodeCount.rounded())),
    primaryColor: Color = PrimaryColor,
    secondaryColor: Color = SecondaryColor,
    glowRadiusDp: Float = \(config.glowRadius)f,
    easing: RingEasing = RingEasing.\(kotlinEasingCaseName(config.easingStyle)),
    springBounce: Double = \(config.springBounce),
    scalePulseEnabled: Boolean = \(config.scalePulseEnabled),
    scalePulseAmount: Double = \(config.scalePulseAmount),
    scalePulseSpeed: Double = \(config.scalePulseSpeed),
    hueShiftEnabled: Boolean = \(config.hueShiftEnabled),
    hueShiftSpeed: Double = \(config.hueShiftSpeed),
    blurRadiusDp: Float = \(config.blurRadius)f,
    blendMode: BlendMode = BlendMode.\(kotlinBlendModeCaseName(config.blendMode)),
    chromaticAberrationEnabled: Boolean = \(config.chromaticAberrationEnabled),
    chromaticAberrationAmountDp: Float = \(config.chromaticAberrationAmount)f,
    particlesEnabled: Boolean = \(config.particlesEnabled),
    particleEmitterShape: String = "\(config.particleEmitterShape.rawValue)",
    particleEmitterMode: String = "\(kotlinEmitterModeCaseName(config.particleEmitterMode))",
    particleEmitterSizeMultiplier: Double = \(config.particleEmitterSizeMultiplier),
    particleRenderMode: String = "\(config.particleRenderMode.rawValue)",
    particleBirthRate: Double = \(config.particleBirthRate),
    particleLifetime: Double = \(config.particleLifetime),
    particleLifetimeRange: Double = \(config.particleLifetimeRange),
    particleVelocityDp: Float = \(config.particleVelocity)f,
    particleVelocityRangeDp: Float = \(config.particleVelocityRange)f,
    particleEmissionLongitudeDegrees: Double = \(config.particleEmissionLongitude),
    particleEmissionSpreadDegrees: Double = \(config.particleEmissionSpread),
    particleXAccelerationDp: Float = \(config.particleXAcceleration)f,
    particleYAccelerationDp: Float = \(config.particleYAcceleration)f,
    particleSpin: Double = \(config.particleSpin),
    particleSpinRange: Double = \(config.particleSpinRange),
    particleScaleDp: Float = \(config.particleScale)f,
    particleScaleRangeDp: Float = \(config.particleScaleRange)f,
    particlePulseEnabled: Boolean = \(config.particlePulseEnabled),
    particlePulsePeriod: Double = \(config.particlePulsePeriod),
    particleBlurRadiusDp: Float = \(config.particleBlurRadius)f
) {
    var elapsedSeconds by remember { mutableStateOf(0.0) }

    LaunchedEffect(Unit) {
        val start = withFrameNanos { it }
        while (true) {
            withFrameNanos { frameTime ->
                elapsedSeconds = (frameTime - start) / 1_000_000_000.0
            }
        }
    }

    fun colors(elapsed: Double): Pair<Color, Color> {
        if (!hueShiftEnabled) return Pair(primaryColor, secondaryColor)
        val raw = (elapsed * hueShiftSpeed) % 1.0
        val hue1 = (if (raw < 0) raw + 1 else raw) * 360.0
        val hue2 = (hue1 + 180.0) % 360.0
        return Pair(
            Color.hsv(hue1.toFloat(), 0.85f, 1f),
            Color.hsv(hue2.toFloat(), 0.85f, 1f)
        )
    }

    val cycles = elapsedSeconds * speed
    val n = floor(cycles)
    val f = cycles - n
    val phase = (n + applyEasing(f, easing, springBounce)) * 2 * Math.PI
    val breathing = if (scalePulseEnabled)
        (1 + scalePulseAmount * sin(elapsedSeconds * scalePulseSpeed * 2 * Math.PI)).toFloat()
    else 1f
    val (p, s) = colors(elapsedSeconds)

    Canvas(
        modifier = modifier
            .size(diameterDp.dp)
            .scale(breathing)
            .blur(blurRadiusDp.dp)
    ) {
        val lineWidthPx = lineWidthDp.dp.toPx()
        val center = Offset(size.width / 2f, size.height / 2f)

        fun sweepBrush(c: Offset, primary: Color, secondary: Color) = Brush.sweepGradient(
            colors = listOf(primary, secondary, primary),
            center = c
        )

        // Deliberately exaggerated RGB split, inspired by Siri's colorful
        // "wavelengths". `p`/`s`/`blendMode` are shadowed locally so the
        // exact same draw calls below run up to 3 times — once per color
        // channel, offset and screen-blended — without a second copy of
        // this function. Needs an explicit `DrawScope.` receiver (even
        // though it's a local function) so the draw calls inside it, and
        // the call sites inside `translate { }` below, resolve correctly.
        fun DrawScope.drawShape(tint: Color?, blendOverride: BlendMode?) {
            val p = tint ?: p
            val s = tint ?: s
            val blendMode = blendOverride ?: blendMode

"""

        let particlesFunc = kotlinParticlesBlock()

        let footer = """
    }
}
"""

        let aberrationDispatch = """
        }

        if (chromaticAberrationEnabled) {
            val offsetPx = chromaticAberrationAmountDp.dp.toPx()
            translate(-offsetPx, offsetPx * 0.3f) { drawShape(Color.Red, BlendMode.Screen) }
            translate(0f, -offsetPx * 0.5f) { drawShape(Color.Green, BlendMode.Screen) }
            translate(offsetPx, offsetPx * 0.3f) { drawShape(Color.Blue, BlendMode.Screen) }
        } else {
            drawShape(null, null)
        }
"""

        // No Diode Mode here. There is no Kotlin port of the diode field
        // — `swiftDiodeSupport` emits Swift — and this generator used to
        // call it, which put `func diodeState(...) -> (color: Color,
        // brightness: Double)` inside a Kotlin file. Compose exports the
        // continuous form until someone writes the Kotlin port; that's a
        // gap, but a gap is better than a file that cannot compile.
        return header + indent(animationBody, by: 12) + aberrationDispatch + "\n"
            + particlesFunc + "\n" + footer
    }

    // MARK: - Web (vanilla HTML/Canvas)

    public static func webCode(config: RingConfig) -> String {
        if let placeholder = patternStyleExportPlaceholder(config: config) { return placeholder }
        let primaryHex = config.primaryColor.hexString
        let secondaryHex = config.secondaryColor.hexString

        let drawBody: String
        switch config.animationType {
        case .wave:
            drawBody = """
const grad = conicGradient(cx, cy, p, s);
ctx.beginPath();
ctx.arc(cx, cy, ringRadius, 0, Math.PI * 2);
ctx.strokeStyle = grad;
ctx.lineWidth = lineWidth;
ctx.lineCap = 'round';
ctx.save();
ctx.translate(cx, cy);
ctx.rotate(phase);
ctx.translate(-cx, -cy);
ctx.stroke();
ctx.restore();
"""
        case .chasing:
            drawBody = """
// Faint full-circle track.
ctx.beginPath();
ctx.arc(cx, cy, ringRadius, 0, Math.PI * 2);
ctx.strokeStyle = withAlpha(p, 0.12);
ctx.lineWidth = lineWidth;
ctx.stroke();

if (config.chasingDrawUndraw) {
  // Classic system-spinner move: the arc starts at absolute angle `phase`
  // (climbing monotonically every frame) and its length pulses
  // 0 -> trailFraction -> 0 once per lap via a sine, so it grows from a
  // point then has its trailing edge sweep forward to erase it — same
  // clockwise direction throughout, never backtracking.
  const cycles = elapsed * config.speed;
  const n = Math.floor(cycles);
  const f = cycles - n;
  const length = Math.max(Math.sin(f * Math.PI) * trailFraction, 0.0001);
  const sweep = length * Math.PI * 2;
  ctx.beginPath();
  ctx.arc(cx, cy, ringRadius, phase, phase + sweep);
  ctx.strokeStyle = conicGradient(cx, cy, p, s);
  ctx.lineWidth = lineWidth;
  ctx.lineCap = 'round';
  ctx.stroke();
} else {
  // Bright trimmed arc that chases around the track.
  const head = phase;
  const sweep = trailFraction * Math.PI * 2;
  ctx.beginPath();
  ctx.arc(cx, cy, ringRadius, head, head + sweep);
  ctx.strokeStyle = conicGradient(cx, cy, p, s);
  ctx.lineWidth = lineWidth;
  ctx.lineCap = 'round';
  ctx.stroke();
}
"""
        case .alternating:
            drawBody = """
const blink = (Math.sin(phase) + 1) / 2;
for (let i = 0; i < diodeCount; i++) {
    const angle = (i / diodeCount) * Math.PI * 2 - Math.PI / 2;
    const isEven = i % 2 === 0;
    const dotColor = isEven ? p : s;
    const dotAlpha = isEven ? blink : 1 - blink;
    const x = cx + Math.cos(angle) * ringRadius;
    const y = cy + Math.sin(angle) * ringRadius;
    ctx.beginPath();
    ctx.arc(x, y, lineWidth / 2, 0, Math.PI * 2);
    ctx.fillStyle = withAlpha(dotColor, dotAlpha);
    ctx.fill();
}
"""
        case .multiChase:
            drawBody = """
const head = phase / (2 * Math.PI);
const tail = Math.max(config.trailFraction, 0.02);
for (let i = 0; i < diodeCount; i++) {
  const position = i / diodeCount;
  let bestIndex = 0, bestBrightness = 0;
  for (let k = 0; k < 2; k++) {
    const cometHead = head + k / 2;
    let behind = (cometHead - position) % 1;
    if (behind < 0) behind += 1;
    if (behind < tail) {
      const brightness = 1 - (behind / tail);
      if (brightness > bestBrightness) { bestBrightness = brightness; bestIndex = k; }
    }
  }
  const angle = position * 2 * Math.PI - Math.PI / 2;
  ctx.beginPath();
  ctx.arc(cx + Math.cos(angle) * radius, cy + Math.sin(angle) * radius, lineWidth / 2, 0, 2 * Math.PI);
  ctx.fillStyle = withAlpha(bestIndex === 0 ? primary(t) : secondary(t), Math.max(bestBrightness, 0.06));
  ctx.fill();
}
"""
        case .bloom:
            drawBody = """
const bloomCount = 6;
const baseGradient = ctx.createConicGradient(-Math.PI / 2, cx, cy);
baseGradient.addColorStop(0, primary(t));
baseGradient.addColorStop(0.5, secondary(t));
baseGradient.addColorStop(1, primary(t));
ctx.save();
ctx.globalAlpha = bloomBase;
ctx.beginPath();
ctx.arc(cx, cy, radius, 0, 2 * Math.PI);
ctx.strokeStyle = baseGradient;
ctx.lineWidth = lineWidth;
ctx.stroke();
ctx.restore();
for (let i = 0; i < bloomCount; i++) {
  const rateSeed = pseudoRandom(i + 211);
  const period = Math.max(6 / Math.max(config.speed, 0.05) * (0.55 + rateSeed), 0.3);
  const local = elapsed / period;
  const cycle = Math.floor(local);
  const f = local - cycle;
  const placeSeed = pseudoRandom2(i, cycle);
  const peakSeed = pseudoRandom2(i, cycle + 4096);
  const driftSeed = pseudoRandom2(i, cycle + 8192);
  const envelope = Math.sin(f * Math.PI);
  const length = Math.max(Math.max(config.trailFraction, 0.02) * (0.33 + peakSeed * 0.67) * envelope, 0.0005);
  const center = placeSeed + (driftSeed - 0.5) * 0.15 * f;
  const intensity = Math.pow(envelope, 1.4) * (0.55 + peakSeed * 0.45);
  const from = (center - length / 2) * 2 * Math.PI - Math.PI / 2;
  ctx.beginPath();
  ctx.arc(cx, cy, radius, from, from + length * 2 * Math.PI);
  ctx.strokeStyle = withAlpha(i % 2 === 0 ? primary(t) : secondary(t), intensity);
  ctx.lineWidth = lineWidth * (0.75 + intensity * 0.5);
  ctx.lineCap = 'round';
  ctx.stroke();
}
"""
        case .pulse:
            drawBody = """
const value = (Math.sin(phase) + 1) / 2;
ctx.beginPath();
ctx.arc(cx, cy, ringRadius, 0, Math.PI * 2);
ctx.strokeStyle = conicGradient(cx, cy, p, s);
ctx.lineWidth = lineWidth * (0.7 + 0.6 * value);
ctx.lineCap = 'round';
ctx.globalAlpha *= (0.55 + 0.45 * value);
ctx.stroke();
ctx.globalAlpha = 1;
"""
        case .ripple:
            drawBody = """
const cycles = elapsed * config.speed;
const n = Math.floor(cycles);
const f = cycles - n;
const waveCount = 3;
ctx.beginPath();
ctx.arc(cx, cy, ringRadius, 0, Math.PI * 2);
ctx.strokeStyle = withAlpha(p, 0.25);
ctx.lineWidth = lineWidth;
ctx.stroke();
for (let i = 0; i < waveCount; i++) {
  const localT = (f + i / waveCount) % 1;
  const waveColor = i % 2 === 0 ? p : s;
  ctx.beginPath();
  ctx.arc(cx, cy, ringRadius * (1 + localT * 0.6), 0, Math.PI * 2);
  ctx.strokeStyle = withAlpha(waveColor, (1 - localT) * 0.8);
  ctx.lineWidth = lineWidth * (1 - localT * 0.5);
  ctx.stroke();
}
"""
        case .wobble:
            drawBody = """
const baseRadius = ringRadius;
const amplitude = config.diameter * 0.035;
const steps = 120;
ctx.beginPath();
for (let i = 0; i <= steps; i++) {
  const t = i / steps;
  const theta = t * Math.PI * 2;
  const wobble = Math.sin(theta * 3 + phase) + Math.sin(theta * 5 - phase * 1.3) * 0.5;
  const radius = baseRadius + amplitude * (wobble / 1.5);
  const x = cx + Math.cos(theta) * radius;
  const y = cy + Math.sin(theta) * radius;
  if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
}
ctx.closePath();
ctx.strokeStyle = conicGradient(cx, cy, p, s);
ctx.lineWidth = lineWidth;
ctx.lineCap = 'round';
ctx.lineJoin = 'round';
ctx.stroke();
"""
        case .equalizer:
            drawBody = """
const count = Math.max(diodeCount, 4);
const segmentSweep = (Math.PI * 2 / count) * 0.7;
ctx.beginPath();
ctx.arc(cx, cy, ringRadius, 0, Math.PI * 2);
ctx.strokeStyle = withAlpha(p, 0.12);
ctx.lineWidth = lineWidth;
ctx.stroke();
for (let i = 0; i < count; i++) {
  const seed = pseudoRandom(i);
  const localPhase = elapsed * config.speed * Math.PI * 2 * (0.6 + seed * 0.8) + seed * Math.PI * 2;
  const value = Math.min((Math.sin(localPhase) + 1) / 2, 1);
  const start = (i / count) * Math.PI * 2;
  const segColor = i % 2 === 0 ? p : s;
  ctx.beginPath();
  ctx.arc(cx, cy, ringRadius, start, start + segmentSweep);
  ctx.strokeStyle = withAlpha(segColor, 0.5 + value * 0.5);
  ctx.lineWidth = lineWidth * (0.3 + value * 0.7);
  ctx.lineCap = 'round';
  ctx.stroke();
}
"""
        case .dualChase:
            drawBody = """
ctx.beginPath();
ctx.arc(cx, cy, ringRadius, 0, Math.PI * 2);
ctx.strokeStyle = withAlpha(p, 0.12);
ctx.lineWidth = lineWidth;
ctx.stroke();

const sweep = trailFraction * Math.PI * 2;
ctx.beginPath();
ctx.arc(cx, cy, ringRadius, phase, phase + sweep);
ctx.strokeStyle = withAlpha(p, 1);
ctx.lineWidth = lineWidth;
ctx.lineCap = 'round';
ctx.stroke();

ctx.beginPath();
ctx.arc(cx, cy, ringRadius, -phase, -phase + sweep);
ctx.strokeStyle = withAlpha(s, 1);
ctx.lineWidth = lineWidth;
ctx.lineCap = 'round';
ctx.stroke();
"""
        case .sparkle:
            drawBody = """
const dotRadius = lineWidth / 2;
ctx.beginPath();
ctx.arc(cx, cy, ringRadius, 0, Math.PI * 2);
ctx.strokeStyle = withAlpha(p, 0.1);
ctx.lineWidth = lineWidth * 0.4;
ctx.stroke();
for (let i = 0; i < diodeCount; i++) {
  const angle = (i / diodeCount) * Math.PI * 2 - Math.PI / 2;
  const seed = pseudoRandom(i);
  const cycles = elapsed * config.speed * (0.5 + seed) + seed * 4;
  const n = Math.floor(cycles);
  const f = cycles - n;
  const brightness = Math.max(0, 1 - f * 4);
  const dotColor = i % 2 === 0 ? p : s;
  const x = cx + Math.cos(angle) * ringRadius;
  const y = cy + Math.sin(angle) * ringRadius;
  ctx.beginPath();
  ctx.arc(x, y, dotRadius * (0.6 + brightness * 0.6), 0, Math.PI * 2);
  ctx.fillStyle = withAlpha(dotColor, 0.15 + brightness * 0.85);
  ctx.fill();
}
"""
        case .aurora:
            drawBody = """
const bandCount = 3;
ctx.beginPath();
ctx.arc(cx, cy, ringRadius, 0, Math.PI * 2);
ctx.strokeStyle = withAlpha(p, 0.08);
ctx.lineWidth = lineWidth * 0.4;
ctx.stroke();
for (let i = 0; i < bandCount; i++) {
  const seed = pseudoRandom(i);
  const bandSpeed = config.speed * (0.12 + seed * 0.22);
  const bandPhase = elapsed * bandSpeed * Math.PI * 2 + seed * Math.PI * 2;
  const bandLength = 0.22 + seed * 0.16;
  const pulse = 0.5 + 0.5 * Math.sin(elapsed * (0.3 + seed * 0.4) + seed * 6);
  const bandColor = i % 2 === 0 ? p : s;
  ctx.beginPath();
  ctx.arc(cx, cy, ringRadius, bandPhase, bandPhase + bandLength * Math.PI * 2);
  ctx.strokeStyle = withAlpha(bandColor, Math.min(0.25 + 0.45 * pulse, 1));
  ctx.lineWidth = lineWidth * 1.5;
  ctx.lineCap = 'round';
  ctx.stroke();
}
"""
        case .liquidFill:
            drawBody = """
const riseCycles = elapsed * config.speed * 0.35;
const levelBase = (Math.sin(riseCycles * Math.PI * 2) + 1) / 2;
const slosh = Math.sin(elapsed * config.speed * Math.PI * 2 * 1.8) * 0.04;
const level = Math.min(Math.max(levelBase + slosh, 0.02), 0.98);
ctx.beginPath();
ctx.arc(cx, cy, ringRadius, 0, Math.PI * 2);
ctx.strokeStyle = withAlpha(p, 0.12);
ctx.lineWidth = lineWidth;
ctx.stroke();
// Angle 0 sits at 3 o'clock in Canvas (as in SwiftUI); starting at Math.PI/2
// (90°) puts the fill's origin at 6 o'clock — bottom — matching the
// SwiftUI/Compose exports' `.rotationEffect(.radians(.pi / 2))`.
ctx.beginPath();
ctx.arc(cx, cy, ringRadius, Math.PI / 2, Math.PI / 2 + level * Math.PI * 2);
ctx.strokeStyle = conicGradient(cx, cy, p, s);
ctx.lineWidth = lineWidth;
ctx.lineCap = 'round';
ctx.stroke();
const capStart = Math.PI / 2 + Math.max(level - 0.015, 0) * Math.PI * 2;
ctx.beginPath();
ctx.arc(cx, cy, ringRadius, capStart, capStart + 0.015 * Math.PI * 2);
ctx.strokeStyle = withAlpha(s, 1);
ctx.lineWidth = lineWidth * 1.3;
ctx.lineCap = 'round';
ctx.stroke();
"""
        }

        return """
<!-- Generated by RingAnimator -->
<!-- Animation: \(config.animationType.rawValue) · Easing: \(config.easingStyle.rawValue) -->
<!--
  Self-contained "AI thinking" ring for the web: a <canvas> driven by
  requestAnimationFrame, using the exact same per-cycle easing, hue-shift,
  and particle math as the SwiftUI/Compose exports, so all three platforms
  stay visually in sync. Drop this file's <div>/<style>/<script> wherever
  the ring should live, or lift the JS into your own animation loop.

  Needs a browser with conic-gradient canvas support (Chrome 90+, Safari
  16.4+, Firefox 113+) for the Wave/Chasing/Pulse color sweep.
-->
<div id="thinking-ring" style="width: \(Int(config.previewDiameter))px; height: \(Int(config.previewDiameter))px;">
  <canvas id="thinking-ring-canvas"></canvas>
</div>

<style>
  #thinking-ring { position: relative; }
  #thinking-ring-canvas { width: 100%; height: 100%; display: block; }
</style>

<script>
(function () {
  const config = {
    diameter: \(Int(config.previewDiameter)),
    lineWidth: \(config.lineWidth),
    speed: \(config.speed), // cycles per second
    trailFraction: \(config.trailFraction),
    bloomBase: \(config.bloomBase),
    bloomSoftness: \(config.bloomSoftness),
    chasingDrawUndraw: \(config.chasingFillStyle == .drawUndraw),
    diodeCount: \(Int(config.diodeCount.rounded())),
    primaryColor: '\(primaryHex)',
    secondaryColor: '\(secondaryHex)',
    glowEnabled: \(config.glowEnabled),
    glowRadius: \(config.glowRadius),

    // Motion effects
    easing: '\(jsEasingCaseName(config.easingStyle))',
    springBounce: \(config.springBounce),
    scalePulseEnabled: \(config.scalePulseEnabled),
    scalePulseAmount: \(config.scalePulseAmount),
    scalePulseSpeed: \(config.scalePulseSpeed),
    hueShiftEnabled: \(config.hueShiftEnabled),
    hueShiftSpeed: \(config.hueShiftSpeed),
    blurRadius: \(config.blurRadius),
    blendMode: '\(jsCompositeOperation(config.blendMode))',
    chromaticAberrationEnabled: \(config.chromaticAberrationEnabled),
    chromaticAberrationAmount: \(config.chromaticAberrationAmount),
    particlesEnabled: \(config.particlesEnabled),
    particleEmitterShape: '\(config.particleEmitterShape.rawValue)',
    particleEmitterMode: '\(swiftEmitterModeCaseName(config.particleEmitterMode))',
    particleEmitterSizeMultiplier: \(config.particleEmitterSizeMultiplier),
    particleRenderMode: '\(config.particleRenderMode.rawValue)',
    particleBirthRate: \(config.particleBirthRate),
    particleLifetime: \(config.particleLifetime),
    particleLifetimeRange: \(config.particleLifetimeRange),
    particleVelocity: \(config.particleVelocity),
    particleVelocityRange: \(config.particleVelocityRange),
    particleEmissionLongitude: \(config.particleEmissionLongitude),
    particleEmissionSpread: \(config.particleEmissionSpread),
    particleXAcceleration: \(config.particleXAcceleration),
    particleYAcceleration: \(config.particleYAcceleration),
    particleSpin: \(config.particleSpin),
    particleSpinRange: \(config.particleSpinRange),
    particleScale: \(config.particleScale),
    particleScaleRange: \(config.particleScaleRange),
    particlePulseEnabled: \(config.particlePulseEnabled),
    particlePulsePeriod: \(config.particlePulsePeriod),
    particleBlurRadius: \(config.particleBlurRadius)
  };

  const container = document.getElementById('thinking-ring');
  const canvas = document.getElementById('thinking-ring-canvas');
  const ctx = canvas.getContext('2d');
  const dpr = window.devicePixelRatio || 1;
  canvas.width = config.diameter * dpr;
  canvas.height = config.diameter * dpr;
  ctx.scale(dpr, dpr);

  // Only needed for chromatic aberration: a reusable offscreen canvas each
  // color-channel pass draws into before being tinted and composited back
  // onto the main canvas — see the `chromaticAberrationEnabled` branch in
  // frame() below.
  const offCanvas = document.createElement('canvas');
  offCanvas.width = canvas.width;
  offCanvas.height = canvas.height;
  const offCtx = offCanvas.getContext('2d');
  offCtx.scale(dpr, dpr);

  function applyEasing(t, style, bounce) {
    switch (style) {
      case 'linear': return t;
      case 'easeIn': return t * t;
      case 'easeOut': return 1 - (1 - t) * (1 - t);
      case 'easeInOut': return t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
      case 'spring': {
        const decay = Math.exp(-6 * t);
        return t + bounce * decay * Math.sin(t * Math.PI * 6);
      }
      default: return t;
    }
  }

  function hexToRgb(hex) {
    const clean = hex.replace('#', '');
    const num = parseInt(clean, 16);
    return { r: (num >> 16) & 255, g: (num >> 8) & 255, b: num & 255 };
  }

  function hsvToRgb(h, s, v) {
    const c = v * s;
    const x = c * (1 - Math.abs(((h / 60) % 2) - 1));
    const m = v - c;
    let r = 0, g = 0, b = 0;
    if (h < 60) { r = c; g = x; b = 0; }
    else if (h < 120) { r = x; g = c; b = 0; }
    else if (h < 180) { r = 0; g = c; b = x; }
    else if (h < 240) { r = 0; g = x; b = c; }
    else if (h < 300) { r = x; g = 0; b = c; }
    else { r = c; g = 0; b = x; }
    return { r: Math.round((r + m) * 255), g: Math.round((g + m) * 255), b: Math.round((b + m) * 255) };
  }

  function withAlpha(rgb, alpha) {
    return 'rgba(' + rgb.r + ',' + rgb.g + ',' + rgb.b + ',' + alpha + ')';
  }

  // Deterministic pseudo-random value in 0..<1 for a given index — used by
  // Equalizer/Sparkle so each segment/point gets its own scattered-looking
  // but fully reproducible rate and phase offset. Same formula as the
  // SwiftUI/Compose exports, so all three stay visually in sync.
  function pseudoRandom(i) {
    const x = Math.sin(i * 12.9898) * 43758.5453;
    return x - Math.floor(x);
  }

  // Two-input hash — Bloom rerolls a patch's position and size on every
  // surfacing, so its seed depends on which surfacing this is.
  function pseudoRandom2(a, b) {
    const x = Math.sin(a * 12.9898 + b * 78.233) * 43758.5453;
    return x - Math.floor(x);
  }

  function colors(elapsed) {
    if (!config.hueShiftEnabled) {
      return { p: hexToRgb(config.primaryColor), s: hexToRgb(config.secondaryColor) };
    }
    const raw = (elapsed * config.hueShiftSpeed) % 1;
    const hue1 = ((raw < 0 ? raw + 1 : raw)) * 360;
    const hue2 = (hue1 + 180) % 360;
    return { p: hsvToRgb(hue1, 0.85, 1), s: hsvToRgb(hue2, 0.85, 1) };
  }

  function conicGradient(cx, cy, p, s) {
    if (ctx.createConicGradient) {
      const grad = ctx.createConicGradient(0, cx, cy);
      grad.addColorStop(0, withAlpha(p, 1));
      grad.addColorStop(0.5, withAlpha(s, 1));
      grad.addColorStop(1, withAlpha(p, 1));
      return grad;
    }
    // Fallback for older browsers: flat primary color.
    return withAlpha(p, 1);
  }

\(jsParticlesFunctions())

  function frame(now) {
    const elapsed = now / 1000;
    const cycles = elapsed * config.speed;
    const n = Math.floor(cycles);
    const f = cycles - n;
    const phase = (n + applyEasing(f, config.easing, config.springBounce)) * 2 * Math.PI;
    const breathing = config.scalePulseEnabled
      ? 1 + config.scalePulseAmount * Math.sin(elapsed * config.scalePulseSpeed * 2 * Math.PI)
      : 1;
    const { p, s } = colors(elapsed);

    const cx = config.diameter / 2;
    const cy = config.diameter / 2;
    const lineWidth = config.lineWidth;
    const trailFraction = config.trailFraction;
    const bloomBase = config.bloomBase;
    const bloomSoftness = config.bloomSoftness;
    const diodeCount = config.diodeCount;
    const ringRadius = config.diameter / 2 - lineWidth / 2 - 4;

    ctx.clearRect(0, 0, config.diameter, config.diameter);
    ctx.save();
    ctx.filter = config.blurRadius > 0 ? 'blur(' + config.blurRadius + 'px)' : 'none';
    ctx.globalCompositeOperation = config.blendMode;
    ctx.shadowColor = config.glowEnabled ? withAlpha(p, 0.7) : 'transparent';
    ctx.shadowBlur = config.glowEnabled ? config.glowRadius : 0;

    ctx.translate(cx, cy);
    ctx.scale(breathing, breathing);
    ctx.translate(-cx, -cy);

    // The shape's draw code itself never references `ctx` beyond this
    // function's own parameter — wrapping it lets the exact same code draw
    // onto either the main canvas or an offscreen one for the chromatic
    // aberration passes below, with zero duplication.
    function drawShape(ctx) {
\(indent(drawBody, by: 6))
    }

    if (config.chromaticAberrationEnabled) {
      const offsetPx = config.chromaticAberrationAmount;
      const passes = [
        { color: 'rgb(255,0,0)', dx: -offsetPx, dy: offsetPx * 0.3 },
        { color: 'rgb(0,255,0)', dx: 0, dy: -offsetPx * 0.5 },
        { color: 'rgb(0,0,255)', dx: offsetPx, dy: offsetPx * 0.3 }
      ];
      for (const pass of passes) {
        offCtx.clearRect(0, 0, config.diameter, config.diameter);
        offCtx.save();
        offCtx.translate(cx, cy);
        offCtx.scale(breathing, breathing);
        offCtx.translate(-cx, -cy);
        drawShape(offCtx);
        offCtx.restore();
        // Isolate to one color channel (componentwise RGB multiply).
        offCtx.globalCompositeOperation = 'multiply';
        offCtx.fillStyle = pass.color;
        offCtx.fillRect(0, 0, config.diameter, config.diameter);
        offCtx.globalCompositeOperation = 'source-over';
        // Composite that channel back, offset and additively (screen)
        // blended — this is what recombines the 3 passes into the
        // exaggerated RGB-split look, Siri-"wavelengths"-style.
        ctx.globalCompositeOperation = 'screen';
        ctx.drawImage(offCanvas, pass.dx, pass.dy, config.diameter, config.diameter);
      }
      ctx.globalCompositeOperation = config.blendMode;
    } else {
      drawShape(ctx);
    }

    if (config.particlesEnabled) {
      drawParticles(elapsed, cx, cy, ringRadius, p, s);
    }

    ctx.restore();
    requestAnimationFrame(frame);
  }

  requestAnimationFrame(frame);
})();
</script>
"""
    }

    // MARK: - Helpers

    /// Turns a cue's free-text name (e.g. "Wi-Fi Connected", "Low Battery
    /// (< 10%)") into a PascalCase Swift identifier fragment (e.g.
    /// "WiFiConnected", "LowBattery10") suitable for a generated struct name.
    private static func swiftIdentifier(from name: String) -> String {
        let words = name
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let pascal = words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
        guard let first = pascal.first, first.isNumber else {
            return pascal.isEmpty ? "Cue" : pascal
        }
        return "Cue" + pascal
    }

    static func indent(_ text: String, by spaces: Int) -> String {
        let pad = String(repeating: " ", count: spaces)
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : pad + $0 }
            .joined(separator: "\n")
    }

    private static func swiftEasingCaseName(_ style: EasingStyle) -> String {
        switch style {
        case .linear: return "linear"
        case .easeIn: return "easeIn"
        case .easeOut: return "easeOut"
        case .easeInOut: return "easeInOut"
        case .spring: return "spring"
        }
    }

    private static func swiftBlendModeCaseName(_ mode: RingBlendMode) -> String {
        switch mode {
        case .normal: return "normal"
        case .screen: return "screen"
        case .plusLighter: return "plusLighter"
        case .colorDodge: return "colorDodge"
        }
    }

    private static func kotlinEasingCaseName(_ style: EasingStyle) -> String {
        switch style {
        case .linear: return "LINEAR"
        case .easeIn: return "EASE_IN"
        case .easeOut: return "EASE_OUT"
        case .easeInOut: return "EASE_IN_OUT"
        case .spring: return "SPRING"
        }
    }

    private static func kotlinBlendModeCaseName(_ mode: RingBlendMode) -> String {
        switch mode {
        case .normal: return "SrcOver"
        case .screen: return "Screen"
        case .plusLighter: return "Plus"
        case .colorDodge: return "ColorDodge"
        }
    }

    private static func jsEasingCaseName(_ style: EasingStyle) -> String {
        swiftEasingCaseName(style)
    }

    private static func jsCompositeOperation(_ mode: RingBlendMode) -> String {
        switch mode {
        case .normal: return "source-over"
        case .screen: return "screen"
        case .plusLighter: return "lighter"
        case .colorDodge: return "color-dodge"
        }
    }

    private static func swiftEmitterModeCaseName(_ mode: ParticleEmitterMode) -> String {
        switch mode {
        case .points: return "points"
        case .outline: return "outline"
        case .surface: return "surface"
        case .volume: return "volume"
        }
    }

    private static func kotlinEmitterModeCaseName(_ mode: ParticleEmitterMode) -> String {
        swiftEmitterModeCaseName(mode)
    }

    // MARK: - Particles
    //
    // Every exported platform reproduces the same raw CAEmitterLayer/
    // CAEmitterCell-style parameters (birth rate, lifetime, velocity,
    // emission spread, spin, scale, pulse) with one generic hand-written
    // formula — there's no longer a preset switch here, since the app
    // itself no longer has one. Compose and the web can't call into real
    // Core Animation, so this stays plain math: birthRate * lifetime
    // approximates the steady-state particle count, velocity * age
    // approximates radial drift, and so on — the same mapping the live
    // preview's CAEmitterCell properties use internally.

    private static func swiftParticlesFunc() -> String {
        """

    private func particles(elapsed: Double, size: CGFloat) -> some View {
        let (p, s) = colors(elapsed: elapsed)
        let ringRadius = size / 2 - lineWidth / 2
        let emitterRadius = ringRadius * CGFloat(max(particleEmitterSizeMultiplier, 0.05))
        let lifetime = max(particleLifetime, 0.05)
        let count = max(Int((particleBirthRate * lifetime).rounded()), 1)
        let longitudeRad = particleEmissionLongitude * Double.pi / 180
        let spreadRad = particleEmissionSpread * Double.pi / 180
        let edgeLike = particleEmitterMode == .points || particleEmitterMode == .outline
        let pulseFactor = particlePulseEnabled
            ? 0.25 + 0.75 * (sin(elapsed * 2 * .pi / max(particlePulsePeriod, 0.05)) + 1) / 2
            : 1.0

        return ZStack {
            ForEach(0..<count, id: \\.self) { i in
                let seed = Double(i)
                let jitter = hash(seed, 0)
                let life = max(lifetime + (hash(seed, 1) - 0.5) * particleLifetimeRange, 0.05)
                let offset = (seed / Double(count)) * life
                let t = (elapsed + offset).truncatingRemainder(dividingBy: life) / life
                let age = t * life
                let vel = max(particleVelocity + (hash(seed, 2) - 0.5) * particleVelocityRange, 0)
                let drift = CGFloat(vel * age)

                // `birthAngle`/`birthRadius`: where the particle is born —
                // exactly on the emitter's edge for .points/.outline, or
                // anywhere inside it for .surface/.volume.
                // Ternaries rather than a deferred-initialization if/else:
                // this sits inside a `ForEach`'s `@ViewBuilder` closure,
                // where a bare `if` is parsed as a conditional *view* and
                // assigning in its branches makes the builder try to
                // conform `()` to `View`. The generated file did not
                // compile because of it.
                let birthAngle = edgeLike
                    ? (seed / Double(count)) * 2 * Double.pi
                    : jitter * 2 * Double.pi
                let birthRadius: CGFloat = edgeLike
                    ? emitterRadius
                    : CGFloat(hash(seed, 3)) * emitterRadius

                // `travelAngle`: emissionLongitude (CAEmitterCell's actual
                // "base direction" property) plus emissionRange's random
                // spread — for edge-like modes this is added on top of the
                // outward normal Core Animation computes automatically for
                // an outline shape.
                let travelAngle = (edgeLike ? birthAngle : 0) + longitudeRad + (jitter - 0.5) * spreadRad

                // Constant acceleration integrated over the particle's own
                // age — real CAEmitterCell.xAcceleration/yAcceleration
                // kinematics (displacement = 1/2 * a * t²).
                let accelX = 0.5 * particleXAcceleration * age * age
                let accelY = 0.5 * particleYAcceleration * age * age

                let dotSize = max(particleScale + CGFloat(hash(seed, 5) - 0.5) * particleScaleRange, 0.5)
                let dotOpacity = (1 - t) * pulseFactor

                Circle()
                    .fill(i.isMultiple(of: 2) ? p : s)
                    .frame(width: dotSize, height: dotSize)
                    .opacity(dotOpacity)
                    .position(
                        x: size / 2 + cos(birthAngle) * birthRadius + cos(travelAngle) * drift + CGFloat(accelX),
                        y: size / 2 + sin(birthAngle) * birthRadius + sin(travelAngle) * drift + CGFloat(accelY)
                    )
            }
        }
        .blur(radius: particleBlurRadius)
    }

    // Deterministic 0...1 pseudo-random hash — same seed always gives the
    // same particle, so particles stay put frame to frame instead of
    // jittering randomly.
    private func hash(_ seed: Double, _ channel: Double) -> Double {
        let x = sin(seed * 12.9898 + channel * 78.233) * 43758.5453
        return x - x.rounded(.down)
    }
"""
    }

    private static func kotlinParticlesBlock() -> String {
        """

        fun hash(seed: Double, channel: Double): Double {
            val x = sin(seed * 12.9898 + channel * 78.233) * 43758.5453
            return x - floor(x)
        }

        if (particlesEnabled) {
            val ringRadius = (size.minDimension / 2f) - (lineWidthPx / 2f)
            val emitterRadius = ringRadius * maxOf(particleEmitterSizeMultiplier, 0.05).toFloat()
            val lifetime = maxOf(particleLifetime, 0.05)
            val count = maxOf((particleBirthRate * lifetime).roundToInt(), 1)
            val longitudeRad = particleEmissionLongitudeDegrees * Math.PI / 180
            val spreadRad = particleEmissionSpreadDegrees * Math.PI / 180
            val edgeLike = particleEmitterMode == "points" || particleEmitterMode == "outline"
            val pulseFactor = if (particlePulseEnabled)
                0.25 + 0.75 * (sin(elapsedSeconds * 2 * Math.PI / maxOf(particlePulsePeriod, 0.05)) + 1) / 2
            else 1.0

            for (i in 0 until count) {
                val seed = i.toDouble()
                val jitter = hash(seed, 0.0)
                val life = maxOf(lifetime + (hash(seed, 1.0) - 0.5) * particleLifetimeRange, 0.05)
                val offset = (seed / count) * life
                val t = ((elapsedSeconds + offset) % life) / life
                val age = t * life
                val vel = maxOf(particleVelocityDp + (hash(seed, 2.0) - 0.5).toFloat() * particleVelocityRangeDp, 0f)
                val drift = (vel * age).toFloat()

                // Birth position: exactly on the emitter edge for
                // points/outline, anywhere inside it for surface/volume.
                val birthAngle: Double
                val birthRadius: Float
                if (edgeLike) {
                    birthAngle = (seed / count) * 2 * Math.PI
                    birthRadius = emitterRadius
                } else {
                    birthAngle = jitter * 2 * Math.PI
                    birthRadius = (hash(seed, 3.0) * emitterRadius).toFloat()
                }

                // Travel direction: emissionLongitude (the real
                // CAEmitterCell base-direction property) plus
                // emissionRange's random spread.
                val travelAngle = (if (edgeLike) birthAngle else 0.0) + longitudeRad + (jitter - 0.5) * spreadRad

                // Constant acceleration integrated over the particle's own
                // age — real xAcceleration/yAcceleration kinematics.
                val accelX = (0.5 * particleXAccelerationDp * age * age).toFloat()
                val accelY = (0.5 * particleYAccelerationDp * age * age).toFloat()

                val dotSize = maxOf(particleScaleDp + (hash(seed, 5.0) - 0.5).toFloat() * particleScaleRangeDp, 0.5f)
                val dotOpacity = ((1 - t) * pulseFactor).toFloat()
                val dotColor = if (i % 2 == 0) p else s
                val x = center.x + (cos(birthAngle) * birthRadius).toFloat() + (cos(travelAngle) * drift).toFloat() + accelX
                val y = center.y + (sin(birthAngle) * birthRadius).toFloat() + (sin(travelAngle) * drift).toFloat() + accelY
                val dotCenter = Offset(x, y)

                // Canvas's DrawScope can't blur just this loop without
                // splitting into a second layered Canvas, so soft focus is
                // approximated with a few widening, fading rings underneath
                // the solid dot — cheap, but reads as blur at small radii.
                if (particleBlurRadiusDp > 0f) {
                    val blurSteps = 4
                    for (bStep in 1..blurSteps) {
                        val spread = particleBlurRadiusDp * (bStep / blurSteps.toFloat())
                        val stepAlpha = dotOpacity * (1f - bStep / (blurSteps + 1f)) * 0.5f
                        drawCircle(
                            color = dotColor.copy(alpha = stepAlpha),
                            radius = dotSize + spread,
                            center = dotCenter,
                            blendMode = blendMode
                        )
                    }
                }
                drawCircle(
                    color = dotColor.copy(alpha = dotOpacity),
                    radius = dotSize,
                    center = dotCenter,
                    blendMode = blendMode
                )
            }
        }
"""
    }

    private static func jsParticlesFunctions() -> String {
        """
  function hash(seed, channel) {
    const x = Math.sin(seed * 12.9898 + channel * 78.233) * 43758.5453;
    return x - Math.floor(x);
  }

  function drawParticles(elapsed, cx, cy, ringRadius, p, s) {
    const emitterRadius = ringRadius * Math.max(config.particleEmitterSizeMultiplier, 0.05);
    const lifetime = Math.max(config.particleLifetime, 0.05);
    const count = Math.max(Math.round(config.particleBirthRate * lifetime), 1);
    const longitudeRad = config.particleEmissionLongitude * Math.PI / 180;
    const spreadRad = config.particleEmissionSpread * Math.PI / 180;
    const edgeLike = config.particleEmitterMode === 'points' || config.particleEmitterMode === 'outline';
    const pulseFactor = config.particlePulseEnabled
      ? 0.25 + 0.75 * (Math.sin(elapsed * 2 * Math.PI / Math.max(config.particlePulsePeriod, 0.05)) + 1) / 2
      : 1;

    for (let i = 0; i < count; i++) {
      const seed = i;
      const jitter = hash(seed, 0);
      const life = Math.max(lifetime + (hash(seed, 1) - 0.5) * config.particleLifetimeRange, 0.05);
      const offset = (seed / count) * life;
      const t = ((elapsed + offset) % life) / life;
      const age = t * life;
      const vel = Math.max(config.particleVelocity + (hash(seed, 2) - 0.5) * config.particleVelocityRange, 0);
      const drift = vel * age;

      // Birth position: exactly on the emitter edge for points/outline,
      // anywhere inside it for surface/volume.
      let birthAngle, birthRadius;
      if (edgeLike) {
        birthAngle = (seed / count) * Math.PI * 2;
        birthRadius = emitterRadius;
      } else {
        birthAngle = jitter * Math.PI * 2;
        birthRadius = hash(seed, 3) * emitterRadius;
      }

      // Travel direction: emissionLongitude (the real CAEmitterCell base-
      // direction property) plus emissionRange's random spread.
      const travelAngle = (edgeLike ? birthAngle : 0) + longitudeRad + (jitter - 0.5) * spreadRad;

      // Constant acceleration integrated over the particle's own age —
      // real xAcceleration/yAcceleration kinematics.
      const accelX = 0.5 * config.particleXAcceleration * age * age;
      const accelY = 0.5 * config.particleYAcceleration * age * age;

      const dotSize = Math.max(config.particleScale + (hash(seed, 5) - 0.5) * config.particleScaleRange, 0.5);
      const dotOpacity = (1 - t) * pulseFactor;
      const dotColor = i % 2 === 0 ? p : s;
      const x = cx + Math.cos(birthAngle) * birthRadius + Math.cos(travelAngle) * drift + accelX;
      const y = cy + Math.sin(birthAngle) * birthRadius + Math.sin(travelAngle) * drift + accelY;

      // Independent of the ring's own blurRadius (already applied to the
      // whole frame by the caller) — canvas 2D's native filter supports a
      // real per-call Gaussian blur, so this is genuine soft focus, not an
      // approximation.
      const previousFilter = ctx.filter;
      ctx.filter = config.particleBlurRadius > 0 ? 'blur(' + config.particleBlurRadius + 'px)' : 'none';
      ctx.beginPath();
      ctx.arc(x, y, dotSize, 0, Math.PI * 2);
      ctx.fillStyle = withAlpha(dotColor, dotOpacity);
      ctx.fill();
      ctx.filter = previousFilter;
    }
  }
"""
    }

    // MARK: - Cue Library export (SwiftUI)
    //
    // Every cue in the Cue Library (`LEDCueParameters`, driven by
    // `LEDPatternStyle` rather than `RingAnimationType` — see
    // `LEDCuePreviewView`, which this mirrors 1:1) can be exported the same
    // way a Nexus animation can. Only the cue's *current* style is
    // baked in (matching how the ring exporters above only emit the
    // currently-selected `RingAnimationType`'s code, not a runtime switch
    // over all of them) — motion effects, particles, and chromatic
    // aberration all reuse the exact same generation approach as the ring
    // exporters.

    public static func swiftUICueCode(cue: LEDCue, parameters: LEDCueParameters) -> String {
        let structName = swiftIdentifier(from: cue.name) + "CueView"
        let clampedSpeed = max(parameters.speed, 0.05)

        let cycleFormula: String
        let contentBody: String
        switch parameters.style {
        case .continuousAnimation:
            // A `.continuousAnimation` cue is authored with the full Nexus
            // animation system (`animationType` + every motion/
            // glow/vibrancy/particle knob) rather than one of the fixed
            // Ziris spec-sheet behaviors below — see `LEDCuePreviewView`,
            // which renders it by handing an equivalent `RingConfig` to
            // `RingView` instead of a template like this one. Exporting
            // *that* system's own generated code is what Nexus's own
            // "Export Code" tab already does (`swiftUICode`
            // above) — switch this cue's Style to a Ziris pattern to export
            // it from here, or copy its `animationType` into Nexus
            // and export from there. This case only exists so the
            // switch stays exhaustive; it falls back to a plain solid ring.
            cycleFormula = "2.0"
            contentBody = "ring(opacity: 1, color: primary(t))"
        case .solid:
            cycleFormula = "2.0"
            contentBody = "ring(opacity: 1, color: primary(t))"
        case .off, .notApplicable:
            cycleFormula = "2.0"
            contentBody = "ring(opacity: 0.06, color: .white)"
        case .earConOnly:
            cycleFormula = "2.0"
            contentBody = """
ZStack {
    Circle().stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
    Image(systemName: "speaker.wave.2.fill")
        .font(.system(size: diameter * 0.28))
        .foregroundStyle(.secondary)
}
"""
        case .flash:
            cycleFormula = "(1.0 / speed) * 2"
            contentBody = """
let period = 1.0 / speed
let on = t.truncatingRemainder(dividingBy: period) < period / 2
ring(opacity: on ? 1 : 0.05, color: primary(t))
"""
        case .quickFlash:
            cycleFormula = "Double(max(flashCount, 1)) * 0.14 * 2 + 0.8"
            contentBody = """
let single = 0.14
let flashWindow = Double(max(flashCount, 1)) * single * 2
// Ternary, not a deferred-initialization if/else: this body is spliced
// into a @ViewBuilder, where `if` reads as a conditional *view* and
// assigning inside its branches makes the builder try to conform `()` to
// `View`.
let on = t < flashWindow && t.truncatingRemainder(dividingBy: single * 2) < single
ring(opacity: on ? 1 : 0.05, color: primary(t))
"""
        case .ripple:
            cycleFormula = "(1.1 / speed) + 0.2"
            contentBody = """
let progress = (t / cycle).truncatingRemainder(dividingBy: 1.0)
ZStack {
    ForEach(0..<2, id: \\.self) { i in
        let rippleOffset = Double(i) * 0.5
        let raw = (progress + rippleOffset).truncatingRemainder(dividingBy: 1.0)
        let eased = applyEasing(raw)
        Circle()
            .stroke(i.isMultiple(of: 2) ? primary(t) : secondary(t), lineWidth: lineWidth * 0.6)
            .scaleEffect(0.55 + 0.55 * eased)
            .opacity(1 - eased)
    }
    ring(opacity: 0.15, color: primary(t), width: lineWidth * 0.4)
}
"""
        // Primitives — one behavior, looping for the whole cycle. Their
        // cycle is `1 / speed` so a generated spin turns exactly once per
        // loop, matching the app (see `LEDPatternStyle.spin`).
        case .spin:
            cycleFormula = "1 / speed"
            contentBody = """
let revolutions = t * speed
let eased = applyEasing(revolutions.truncatingRemainder(dividingBy: 1))
let angle = (revolutions.rounded(.down) + eased) * 2 * .pi
ZStack {
    Circle().stroke(primary(t).opacity(0.12), lineWidth: lineWidth)
    Circle()
        .trim(from: 0, to: 0.28)
        .stroke(primary(t), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        .rotationEffect(.radians(angle))
}
"""
        case .pulseAccelerate:
            cycleFormula = "2.2"
            contentBody = """
let local = t.truncatingRemainder(dividingBy: 2.2)
let rate = 1.5 + (local / 2.2) * 8
let value = (sin(local * rate * 2 * .pi) + 1) / 2
ring(opacity: 0.4 + 0.6 * value, color: primary(t), width: lineWidth * CGFloat(0.7 + 0.5 * value))
"""
        case .rainbow:
            cycleFormula = "1 / speed"
            contentBody = """
let hue = (t * speed).truncatingRemainder(dividingBy: 1)
ring(opacity: 1, color: Color(hue: hue, saturation: 0.85, brightness: 1))
"""
        case .transitionToSolid:
            cycleFormula = "0.5 + holdSeconds + 0.5"
            contentBody = """
let rampIn = 0.5
let holdEnd = rampIn + holdSeconds
// Ternary chain rather than a deferred-initialization if/else — see the
// note in `.quickFlash` above.
let opacity = t < rampIn ? t / rampIn : (t < holdEnd ? 1 : 0.05)
ring(opacity: max(opacity, 0.05), color: primary(t))
"""
        case .spinThenSolidFade:
            cycleFormula = "(1.1 / speed) + holdSeconds + fadeOutSeconds + 0.6"
            contentBody = """
let spinDuration = 1.1 / speed
let holdEnd = spinDuration + holdSeconds
if t < spinDuration {
    let head = t / spinDuration
    let easedHead = applyEasing(head)
    ZStack {
        Circle().stroke(primary(t).opacity(0.12), lineWidth: lineWidth)
        Circle()
            .trim(from: 0, to: 0.28)
            .stroke(primary(t), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.radians(easedHead * 2 * Double.pi * 3))
    }
    .shadow(color: primary(t).opacity(0.6), radius: 8)
} else if t < holdEnd {
    ring(opacity: 1, color: primary(t))
} else {
    let fadeProgress = fadeOutSeconds > 0 ? (t - holdEnd) / fadeOutSeconds : 1
    ring(opacity: max(1 - fadeProgress, 0.05), color: primary(t))
}
"""
        case .pulseAccelerateThenSolidFade:
            cycleFormula = "2.2 + holdSeconds + fadeOutSeconds + 0.6"
            contentBody = """
let pulseDuration = 2.2
let holdEnd = pulseDuration + holdSeconds
if t < pulseDuration {
    let progress = t / pulseDuration
    let rate = 1.5 + progress * 8
    let value = (sin(t * rate * 2 * Double.pi) + 1) / 2
    ring(opacity: 0.4 + 0.6 * value, color: primary(t), width: lineWidth * CGFloat(0.7 + 0.5 * value))
} else if t < holdEnd {
    ring(opacity: 1, color: primary(t))
} else {
    let fadeProgress = fadeOutSeconds > 0 ? (t - holdEnd) / fadeOutSeconds : 1
    ring(opacity: max(1 - fadeProgress, 0.05), color: primary(t))
}
"""
        case .rainbowThenWhiteFade:
            cycleFormula = "(1.5 / speed) + holdSeconds + fadeOutSeconds + 0.6"
            contentBody = """
let spinDuration = 1.5 / speed
let holdEnd = spinDuration + holdSeconds
if t < spinDuration {
    let hue = t / spinDuration
    ring(opacity: 1, color: Color(hue: hue, saturation: 0.85, brightness: 1))
} else if t < holdEnd {
    ring(opacity: 1, color: .white)
} else {
    let fadeProgress = fadeOutSeconds > 0 ? (t - holdEnd) / fadeOutSeconds : 1
    ring(opacity: max(1 - fadeProgress, 0.05), color: .white)
}
"""
        case .voiceAssistantColor:
            cycleFormula = "2.4 / speed"
            contentBody = """
let voicePhase = t * speed * 2 * Double.pi
let gradient = AngularGradient(colors: [primary(t), secondary(t), primary(t)], center: .center)
Circle()
    .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
    .rotationEffect(.radians(voicePhase))
    .shadow(color: primary(t).opacity(0.5), radius: 8)
"""
        case .custom:
            cycleFormula = "2.0"
            contentBody = "ring(opacity: 0.5, color: primary(t))"
        }

        let header = """
// Generated by RingAnimator
// Cue: \(cue.name) (\([cue.category, cue.subcategory].compactMap { $0 }.joined(separator: " · ")))
// Style: \(parameters.style.displayName)
//
// Drop this file into your iOS app. Self-contained — no dependencies
// beyond SwiftUI.
//
// Spec sheet reference: \(cue.specText)

import SwiftUI

struct \(structName): View {
    var diameter: CGFloat = 160
    var lineWidth: CGFloat = 12
    var speed: Double = \(clampedSpeed)
    var flashCount: Int = \(parameters.flashCount)
    var holdSeconds: Double = \(parameters.holdSeconds)
    var fadeOutSeconds: Double = \(parameters.fadeOutSeconds)
    var primaryColor: Color = Color(hex: "\(parameters.primaryColorHex)")
    var secondaryColor: Color = Color(hex: "\(parameters.secondaryColorHex)")

    // Motion effects
    var easing: Easing = .\(swiftEasingCaseName(parameters.easingStyle))
    var springBounce: Double = \(parameters.springBounce)
    var scalePulseEnabled: Bool = \(parameters.scalePulseEnabled)
    var scalePulseAmount: Double = \(parameters.scalePulseAmount)
    var scalePulseSpeed: Double = \(parameters.scalePulseSpeed)
    var hueShiftEnabled: Bool = \(parameters.hueShiftEnabled)
    var hueShiftSpeed: Double = \(parameters.hueShiftSpeed)
    var blurRadius: CGFloat = \(parameters.blurRadius)
    var blendMode: BlendMode = .\(swiftBlendModeCaseName(parameters.blendMode))
    // Deliberately exaggerated RGB split — see `aberratedRing`.
    var chromaticAberrationEnabled: Bool = \(parameters.chromaticAberrationEnabled)
    var chromaticAberrationAmount: CGFloat = \(parameters.chromaticAberrationAmount)

    // Particles — literal CAEmitterLayer/CAEmitterCell parameters, same
    // hand-written approximation Nexus's own export uses.
    var particlesEnabled: Bool = \(parameters.particlesEnabled)
    var particleEmitterShape: String = "\(parameters.particleEmitterShape.rawValue)"
    var particleEmitterMode: ParticleEmitterMode = .\(swiftEmitterModeCaseName(parameters.particleEmitterMode))
    var particleEmitterSizeMultiplier: Double = \(parameters.particleEmitterSizeMultiplier)
    var particleRenderMode: String = "\(parameters.particleRenderMode.rawValue)"
    var particleBirthRate: Double = \(parameters.particleBirthRate)
    var particleLifetime: Double = \(parameters.particleLifetime)
    var particleLifetimeRange: Double = \(parameters.particleLifetimeRange)
    var particleVelocity: Double = \(parameters.particleVelocity)
    var particleVelocityRange: Double = \(parameters.particleVelocityRange)
    var particleEmissionLongitude: Double = \(parameters.particleEmissionLongitude)
    var particleEmissionSpread: Double = \(parameters.particleEmissionSpread)
    var particleXAcceleration: Double = \(parameters.particleXAcceleration)
    var particleYAcceleration: Double = \(parameters.particleYAcceleration)
    var particleSpin: Double = \(parameters.particleSpin)
    var particleSpinRange: Double = \(parameters.particleSpinRange)
    var particleScale: CGFloat = \(parameters.particleScale)
    var particleScaleRange: CGFloat = \(parameters.particleScaleRange)
    var particlePulseEnabled: Bool = \(parameters.particlePulseEnabled)
    var particlePulsePeriod: Double = \(parameters.particlePulsePeriod)
    var particleBlurRadius: CGFloat = \(parameters.particleBlurRadius)

    enum Easing {
        case linear, easeIn, easeOut, easeInOut, spring
    }

    enum ParticleEmitterMode {
        case points, outline, surface, volume
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            let cycle = max(\(cycleFormula), 0.2)
            let t = elapsed.truncatingRemainder(dividingBy: cycle)
            let breathing = scalePulseEnabled
                ? 1 + scalePulseAmount * sin(elapsed * scalePulseSpeed * 2 * Double.pi)
                : 1

            ZStack {
                if particlesEnabled {
                    particles(elapsed: elapsed, size: diameter)
                }
                aberratedContent(t: t, cycle: cycle)
            }
            .frame(width: diameter, height: diameter)
            .scaleEffect(breathing)
            .blur(radius: blurRadius)
            .compositingGroup()
            .blendMode(blendMode)
        }
    }

    // Deliberately exaggerated RGB split, inspired by Siri's colorful
    // "wavelengths" — universal post-process, doesn't touch `content(t:cycle:)`.
    @ViewBuilder
    private func aberratedContent(t: Double, cycle: Double) -> some View {
        if chromaticAberrationEnabled {
            ZStack {
                content(t: t, cycle: cycle)
                    .colorMultiply(.red)
                    .blendMode(.screen)
                    .offset(x: -chromaticAberrationAmount, y: chromaticAberrationAmount * 0.3)
                content(t: t, cycle: cycle)
                    .colorMultiply(.green)
                    .blendMode(.screen)
                    .offset(x: 0, y: -chromaticAberrationAmount * 0.5)
                content(t: t, cycle: cycle)
                    .colorMultiply(.blue)
                    .blendMode(.screen)
                    .offset(x: chromaticAberrationAmount, y: chromaticAberrationAmount * 0.3)
            }
            .compositingGroup()
        } else {
            content(t: t, cycle: cycle)
        }
    }

    @ViewBuilder
    private func content(t: Double, cycle: Double) -> some View {
"""

        let particlesFunc = swiftParticlesFunc()

        let footer = """

    private func applyEasing(_ t: Double) -> Double {
        switch easing {
        case .linear: return t
        case .easeIn: return t * t
        case .easeOut: return 1 - (1 - t) * (1 - t)
        case .easeInOut: return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        case .spring:
            let decay = exp(-6 * t)
            return t + springBounce * decay * sin(t * Double.pi * 6)
        }
    }

    private func hueColor(t: Double, offset: Double) -> Color {
        let raw = (t * hueShiftSpeed).truncatingRemainder(dividingBy: 1)
        let hue = ((raw < 0 ? raw + 1 : raw) + offset).truncatingRemainder(dividingBy: 1)
        return Color(hue: hue, saturation: 0.85, brightness: 1)
    }

    private func primary(_ t: Double) -> Color {
        hueShiftEnabled ? hueColor(t: t, offset: 0) : primaryColor
    }

    private func secondary(_ t: Double) -> Color {
        hueShiftEnabled ? hueColor(t: t, offset: 0.5) : secondaryColor
    }

    // Used by `particles(elapsed:)` below — same hue-shift math as
    // `primary`/`secondary`, just keyed on raw elapsed time instead of the
    // pattern's own looping `t`, since particles drift continuously rather
    // than looping with the pattern.
    private func colors(elapsed: Double) -> (Color, Color) {
        guard hueShiftEnabled else { return (primaryColor, secondaryColor) }
        let raw = (elapsed * hueShiftSpeed).truncatingRemainder(dividingBy: 1)
        let hue1 = raw < 0 ? raw + 1 : raw
        let hue2 = (hue1 + 0.5).truncatingRemainder(dividingBy: 1)
        return (
            Color(hue: hue1, saturation: 0.85, brightness: 1),
            Color(hue: hue2, saturation: 0.85, brightness: 1)
        )
    }

    private func ring(opacity: Double, color: Color, width: CGFloat? = nil) -> some View {
        Circle()
            .stroke(color, style: StrokeStyle(lineWidth: width ?? lineWidth, lineCap: .round))
            .opacity(opacity)
            .shadow(color: color.opacity(opacity * 0.7), radius: opacity > 0 ? 10 : 0)
    }
}

// MARK: - Hex color helper
extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")))
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
"""

        return header + "\n" + indent(contentBody, by: 8) + "\n    }\n" + particlesFunc + footer
    }

    // MARK: - Cue Library export (Jetpack Compose)

    public static func composeCueCode(cue: LEDCue, parameters: LEDCueParameters) -> String {
        let functionName = swiftIdentifier(from: cue.name) + "CueView"
        let primaryHex = Color(hex: parameters.primaryColorHex).hexString.replacingOccurrences(of: "#", with: "")
        let secondaryHex = Color(hex: parameters.secondaryColorHex).hexString.replacingOccurrences(of: "#", with: "")
        let clampedSpeed = max(parameters.speed, 0.05)

        let cycleFormula: String
        let contentBody: String
        switch parameters.style {
        case .continuousAnimation:
            // See the matching case in `swiftUICueCode` above — this cue is
            // authored via the full Nexus animation system, not one
            // of the Ziris patterns below. Falls back to a plain solid ring
            // just to keep this switch exhaustive.
            cycleFormula = "2.0"
            contentBody = """
drawArc(
    color = p,
    startAngle = 0f,
    sweepAngle = 360f,
    useCenter = false,
    style = Stroke(width = lineWidthPx, cap = StrokeCap.Round),
    blendMode = blendMode
)
"""
        case .solid:
            cycleFormula = "2.0"
            contentBody = """
drawArc(
    color = p,
    startAngle = 0f,
    sweepAngle = 360f,
    useCenter = false,
    style = Stroke(width = lineWidthPx, cap = StrokeCap.Round),
    blendMode = blendMode
)
"""
        case .off, .notApplicable:
            cycleFormula = "2.0"
            contentBody = """
drawArc(
    color = Color.White.copy(alpha = 0.06f),
    startAngle = 0f,
    sweepAngle = 360f,
    useCenter = false,
    style = Stroke(width = lineWidthPx, cap = StrokeCap.Round),
    blendMode = blendMode
)
"""
        case .earConOnly:
            cycleFormula = "2.0"
            contentBody = """
drawArc(
    color = Color.White.copy(alpha = 0.08f),
    startAngle = 0f,
    sweepAngle = 360f,
    useCenter = false,
    style = Stroke(width = lineWidthPx)
)
// No LED animation for this cue — layer your own "speaker" icon in
// Compose UI on top of this Canvas; Canvas alone can't draw SF Symbols.
"""
        case .flash:
            cycleFormula = "(1.0 / speed) * 2"
            contentBody = """
val period = 1.0 / speed
val on = (t % period) < period / 2
drawArc(
    color = p.copy(alpha = if (on) 1f else 0.05f),
    startAngle = 0f,
    sweepAngle = 360f,
    useCenter = false,
    style = Stroke(width = lineWidthPx, cap = StrokeCap.Round),
    blendMode = blendMode
)
"""
        case .quickFlash:
            cycleFormula = "maxOf(flashCount, 1) * 0.14 * 2 + 0.8"
            contentBody = """
val single = 0.14
val flashWindow = maxOf(flashCount, 1) * single * 2
val on = if (t < flashWindow) (t % (single * 2)) < single else false
drawArc(
    color = p.copy(alpha = if (on) 1f else 0.05f),
    startAngle = 0f,
    sweepAngle = 360f,
    useCenter = false,
    style = Stroke(width = lineWidthPx, cap = StrokeCap.Round),
    blendMode = blendMode
)
"""
        case .ripple:
            cycleFormula = "(1.1 / speed) + 0.2"
            contentBody = """
val progress = (t / cycle) % 1.0
val baseRadius = size.minDimension / 2f
for (i in 0 until 2) {
    val rippleOffset = i * 0.5
    val raw = (progress + rippleOffset) % 1.0
    val eased = applyEasing(raw, easing, springBounce).toFloat()
    val rippleColor = if (i % 2 == 0) p else s
    drawCircle(
        color = rippleColor.copy(alpha = 1f - eased),
        radius = baseRadius * (0.55f + 0.55f * eased),
        center = center,
        style = Stroke(width = lineWidthPx * 0.6f),
        blendMode = blendMode
    )
}
drawCircle(
    color = p.copy(alpha = 0.15f),
    radius = baseRadius,
    center = center,
    style = Stroke(width = lineWidthPx * 0.4f),
    blendMode = blendMode
)
"""
        case .spin:
            cycleFormula = "1 / speed"
            contentBody = """
val revolutions = t * speed
val eased = applyEasing(revolutions % 1.0)
val angle = ((floor(revolutions) + eased) * 360.0).toFloat()
drawCircle(
    color = primary(t).copy(alpha = 0.12f),
    radius = radiusPx,
    style = Stroke(width = lineWidthPx)
)
rotate(degrees = angle) {
    drawArc(
        color = primary(t),
        startAngle = -90f,
        sweepAngle = 100.8f,
        useCenter = false,
        style = Stroke(width = lineWidthPx, cap = StrokeCap.Round)
    )
}
"""
        case .pulseAccelerate:
            cycleFormula = "2.2"
            contentBody = """
val local = t % 2.2
val rate = 1.5 + (local / 2.2) * 8
val value = ((sin(local * rate * 2 * PI) + 1) / 2).toFloat()
drawCircle(
    color = primary(t).copy(alpha = 0.4f + 0.6f * value),
    radius = radiusPx,
    style = Stroke(width = lineWidthPx * (0.7f + 0.5f * value), cap = StrokeCap.Round)
)
"""
        case .rainbow:
            cycleFormula = "1 / speed"
            contentBody = """
val hue = ((t * speed) % 1.0).toFloat()
drawCircle(
    color = Color.hsv(hue * 360f, 0.85f, 1f),
    radius = radiusPx,
    style = Stroke(width = lineWidthPx, cap = StrokeCap.Round)
)
"""
        case .transitionToSolid:
            cycleFormula = "0.5 + holdSeconds + 0.5"
            contentBody = """
val rampIn = 0.5
val holdEnd = rampIn + holdSeconds
val opacity = when {
    t < rampIn -> t / rampIn
    t < holdEnd -> 1.0
    else -> 0.05
}
drawArc(
    color = p.copy(alpha = maxOf(opacity, 0.05).toFloat()),
    startAngle = 0f,
    sweepAngle = 360f,
    useCenter = false,
    style = Stroke(width = lineWidthPx, cap = StrokeCap.Round),
    blendMode = blendMode
)
"""
        case .spinThenSolidFade:
            cycleFormula = "(1.1 / speed) + holdSeconds + fadeOutSeconds + 0.6"
            contentBody = """
val spinDuration = 1.1 / speed
val holdEnd = spinDuration + holdSeconds
if (t < spinDuration) {
    val head = t / spinDuration
    val easedHead = applyEasing(head, easing, springBounce)
    drawArc(
        color = p.copy(alpha = 0.12f),
        startAngle = 0f,
        sweepAngle = 360f,
        useCenter = false,
        style = Stroke(width = lineWidthPx)
    )
    drawArc(
        color = p,
        startAngle = Math.toDegrees(easedHead * 2 * Math.PI * 3).toFloat(),
        sweepAngle = 360f * 0.28f,
        useCenter = false,
        style = Stroke(width = lineWidthPx, cap = StrokeCap.Round),
        blendMode = blendMode
    )
} else if (t < holdEnd) {
    drawArc(
        color = p,
        startAngle = 0f,
        sweepAngle = 360f,
        useCenter = false,
        style = Stroke(width = lineWidthPx, cap = StrokeCap.Round),
        blendMode = blendMode
    )
} else {
    val fadeProgress = if (fadeOutSeconds > 0) (t - holdEnd) / fadeOutSeconds else 1.0
    drawArc(
        color = p.copy(alpha = maxOf(1 - fadeProgress, 0.05).toFloat()),
        startAngle = 0f,
        sweepAngle = 360f,
        useCenter = false,
        style = Stroke(width = lineWidthPx, cap = StrokeCap.Round),
        blendMode = blendMode
    )
}
"""
        case .pulseAccelerateThenSolidFade:
            cycleFormula = "2.2 + holdSeconds + fadeOutSeconds + 0.6"
            contentBody = """
val pulseDuration = 2.2
val holdEnd = pulseDuration + holdSeconds
if (t < pulseDuration) {
    val progress = t / pulseDuration
    val rate = 1.5 + progress * 8
    val value = (sin(t * rate * 2 * Math.PI) + 1) / 2
    drawArc(
        color = p.copy(alpha = (0.4 + 0.6 * value).toFloat()),
        startAngle = 0f,
        sweepAngle = 360f,
        useCenter = false,
        style = Stroke(width = (lineWidthPx * (0.7 + 0.5 * value)).toFloat(), cap = StrokeCap.Round),
        blendMode = blendMode
    )
} else if (t < holdEnd) {
    drawArc(
        color = p,
        startAngle = 0f,
        sweepAngle = 360f,
        useCenter = false,
        style = Stroke(width = lineWidthPx, cap = StrokeCap.Round),
        blendMode = blendMode
    )
} else {
    val fadeProgress = if (fadeOutSeconds > 0) (t - holdEnd) / fadeOutSeconds else 1.0
    drawArc(
        color = p.copy(alpha = maxOf(1 - fadeProgress, 0.05).toFloat()),
        startAngle = 0f,
        sweepAngle = 360f,
        useCenter = false,
        style = Stroke(width = lineWidthPx, cap = StrokeCap.Round),
        blendMode = blendMode
    )
}
"""
        case .rainbowThenWhiteFade:
            cycleFormula = "(1.5 / speed) + holdSeconds + fadeOutSeconds + 0.6"
            contentBody = """
val spinDuration = 1.5 / speed
val holdEnd = spinDuration + holdSeconds
if (t < spinDuration) {
    val hue = ((t / spinDuration) * 360.0).toFloat()
    drawArc(
        color = Color.hsv(hue, 0.85f, 1f),
        startAngle = 0f,
        sweepAngle = 360f,
        useCenter = false,
        style = Stroke(width = lineWidthPx, cap = StrokeCap.Round),
        blendMode = blendMode
    )
} else if (t < holdEnd) {
    drawArc(
        color = Color.White,
        startAngle = 0f,
        sweepAngle = 360f,
        useCenter = false,
        style = Stroke(width = lineWidthPx, cap = StrokeCap.Round),
        blendMode = blendMode
    )
} else {
    val fadeProgress = if (fadeOutSeconds > 0) (t - holdEnd) / fadeOutSeconds else 1.0
    drawArc(
        color = Color.White.copy(alpha = maxOf(1 - fadeProgress, 0.05).toFloat()),
        startAngle = 0f,
        sweepAngle = 360f,
        useCenter = false,
        style = Stroke(width = lineWidthPx, cap = StrokeCap.Round),
        blendMode = blendMode
    )
}
"""
        case .voiceAssistantColor:
            cycleFormula = "2.4 / speed"
            contentBody = """
val voicePhase = t * speed * 2 * Math.PI
drawArc(
    brush = Brush.sweepGradient(colors = listOf(p, s, p), center = center),
    startAngle = Math.toDegrees(voicePhase).toFloat(),
    sweepAngle = 360f,
    useCenter = false,
    style = Stroke(width = lineWidthPx, cap = StrokeCap.Round),
    blendMode = blendMode
)
"""
        case .custom:
            cycleFormula = "2.0"
            contentBody = """
drawArc(
    color = p.copy(alpha = 0.5f),
    startAngle = 0f,
    sweepAngle = 360f,
    useCenter = false,
    style = Stroke(width = lineWidthPx, cap = StrokeCap.Round),
    blendMode = blendMode
)
"""
        }

        let header = """
// Generated by RingAnimator
// Cue: \(cue.name) (\([cue.category, cue.subcategory].compactMap { $0 }.joined(separator: " · ")))
// Style: \(parameters.style.displayName)
//
// Drop this file into your Android app.
//
// Spec sheet reference: \(cue.specText)

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.unit.dp
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin

private val PrimaryColor = Color(0xFF\(primaryHex))
private val SecondaryColor = Color(0xFF\(secondaryHex))

enum class RingEasing { LINEAR, EASE_IN, EASE_OUT, EASE_IN_OUT, SPRING }

private fun applyEasing(t: Double, easing: RingEasing, bounce: Double): Double = when (easing) {
    RingEasing.LINEAR -> t
    RingEasing.EASE_IN -> t * t
    RingEasing.EASE_OUT -> 1 - (1 - t) * (1 - t)
    RingEasing.EASE_IN_OUT -> if (t < 0.5) 2 * t * t else 1 - (-2 * t + 2).pow(2) / 2
    RingEasing.SPRING -> {
        val decay = exp(-6 * t)
        t + bounce * decay * sin(t * Math.PI * 6)
    }
}

@Composable
fun \(functionName)(
    modifier: Modifier = Modifier,
    diameterDp: Int = 160,
    lineWidthDp: Float = 12f,
    speed: Double = \(clampedSpeed),
    flashCount: Int = \(parameters.flashCount),
    holdSeconds: Double = \(parameters.holdSeconds),
    fadeOutSeconds: Double = \(parameters.fadeOutSeconds),
    primaryColor: Color = PrimaryColor,
    secondaryColor: Color = SecondaryColor,
    easing: RingEasing = RingEasing.\(kotlinEasingCaseName(parameters.easingStyle)),
    springBounce: Double = \(parameters.springBounce),
    scalePulseEnabled: Boolean = \(parameters.scalePulseEnabled),
    scalePulseAmount: Double = \(parameters.scalePulseAmount),
    scalePulseSpeed: Double = \(parameters.scalePulseSpeed),
    hueShiftEnabled: Boolean = \(parameters.hueShiftEnabled),
    hueShiftSpeed: Double = \(parameters.hueShiftSpeed),
    blurRadiusDp: Float = \(parameters.blurRadius)f,
    blendMode: BlendMode = BlendMode.\(kotlinBlendModeCaseName(parameters.blendMode)),
    chromaticAberrationEnabled: Boolean = \(parameters.chromaticAberrationEnabled),
    chromaticAberrationAmountDp: Float = \(parameters.chromaticAberrationAmount)f,
    particlesEnabled: Boolean = \(parameters.particlesEnabled),
    particleEmitterShape: String = "\(parameters.particleEmitterShape.rawValue)",
    particleEmitterMode: String = "\(kotlinEmitterModeCaseName(parameters.particleEmitterMode))",
    particleEmitterSizeMultiplier: Double = \(parameters.particleEmitterSizeMultiplier),
    particleRenderMode: String = "\(parameters.particleRenderMode.rawValue)",
    particleBirthRate: Double = \(parameters.particleBirthRate),
    particleLifetime: Double = \(parameters.particleLifetime),
    particleLifetimeRange: Double = \(parameters.particleLifetimeRange),
    particleVelocityDp: Float = \(parameters.particleVelocity)f,
    particleVelocityRangeDp: Float = \(parameters.particleVelocityRange)f,
    particleEmissionLongitudeDegrees: Double = \(parameters.particleEmissionLongitude),
    particleEmissionSpreadDegrees: Double = \(parameters.particleEmissionSpread),
    particleXAccelerationDp: Float = \(parameters.particleXAcceleration)f,
    particleYAccelerationDp: Float = \(parameters.particleYAcceleration)f,
    particleSpin: Double = \(parameters.particleSpin),
    particleSpinRange: Double = \(parameters.particleSpinRange),
    particleScaleDp: Float = \(parameters.particleScale)f,
    particleScaleRangeDp: Float = \(parameters.particleScaleRange)f,
    particlePulseEnabled: Boolean = \(parameters.particlePulseEnabled),
    particlePulsePeriod: Double = \(parameters.particlePulsePeriod),
    particleBlurRadiusDp: Float = \(parameters.particleBlurRadius)f
) {
    var elapsedSeconds by remember { mutableStateOf(0.0) }

    LaunchedEffect(Unit) {
        val start = withFrameNanos { it }
        while (true) {
            withFrameNanos { frameTime ->
                elapsedSeconds = (frameTime - start) / 1_000_000_000.0
            }
        }
    }

    fun hueColor(t: Double, offset: Double): Color {
        val raw = (t * hueShiftSpeed) % 1.0
        val hue = (((if (raw < 0) raw + 1 else raw) + offset) % 1.0) * 360.0
        return Color.hsv(hue.toFloat(), 0.85f, 1f)
    }

    fun primary(t: Double): Color = if (hueShiftEnabled) hueColor(t, 0.0) else primaryColor
    fun secondary(t: Double): Color = if (hueShiftEnabled) hueColor(t, 0.5) else secondaryColor

    fun colors(elapsed: Double): Pair<Color, Color> {
        if (!hueShiftEnabled) return Pair(primaryColor, secondaryColor)
        val raw = (elapsed * hueShiftSpeed) % 1.0
        val hue1 = (if (raw < 0) raw + 1 else raw) * 360.0
        val hue2 = (hue1 + 180.0) % 360.0
        return Pair(
            Color.hsv(hue1.toFloat(), 0.85f, 1f),
            Color.hsv(hue2.toFloat(), 0.85f, 1f)
        )
    }

    val cycle = maxOf(\(cycleFormula), 0.2)
    val t = elapsedSeconds % cycle
    val breathing = if (scalePulseEnabled)
        (1 + scalePulseAmount * sin(elapsedSeconds * scalePulseSpeed * 2 * Math.PI)).toFloat()
    else 1f
    val (p, s) = colors(elapsedSeconds)

    Canvas(
        modifier = modifier
            .size(diameterDp.dp)
            .scale(breathing)
            .blur(blurRadiusDp.dp)
    ) {
        val lineWidthPx = lineWidthDp.dp.toPx()
        val center = Offset(size.width / 2f, size.height / 2f)

        // Deliberately exaggerated RGB split, inspired by Siri's colorful
        // "wavelengths". `p`/`s`/`blendMode` are shadowed locally so the
        // exact same draw calls below run up to 3 times — once per color
        // channel, offset and screen-blended.
        fun DrawScope.drawShape(tint: Color?, blendOverride: BlendMode?) {
            val p = tint ?: primary(t)
            val s = tint ?: secondary(t)
            val blendMode = blendOverride ?: blendMode

"""

        let particlesFunc = kotlinParticlesBlock()

        let footer = """
    }
}
"""

        let aberrationDispatch = """
        }

        if (chromaticAberrationEnabled) {
            val offsetPx = chromaticAberrationAmountDp.dp.toPx()
            translate(-offsetPx, offsetPx * 0.3f) { drawShape(Color.Red, BlendMode.Screen) }
            translate(0f, -offsetPx * 0.5f) { drawShape(Color.Green, BlendMode.Screen) }
            translate(offsetPx, offsetPx * 0.3f) { drawShape(Color.Blue, BlendMode.Screen) }
        } else {
            drawShape(null, null)
        }
"""

        return header + indent(contentBody, by: 12) + aberrationDispatch + "\n" + particlesFunc + "\n" + footer
    }

    // MARK: - Cue Library export (Web / Canvas)

    public static func webCueCode(cue: LEDCue, parameters: LEDCueParameters) -> String {
        let idSuffix = swiftIdentifier(from: cue.name)

        let cycleFormula: String
        let drawBody: String
        switch parameters.style {
        case .continuousAnimation:
            // See the matching case in `swiftUICueCode` above — this cue is
            // authored via the full Nexus animation system, not one
            // of the Ziris patterns below. Falls back to a plain solid ring
            // just to keep this switch exhaustive.
            cycleFormula = "2.0"
            drawBody = """
ctx.beginPath();
ctx.arc(cx, cy, ringRadius, 0, Math.PI * 2);
ctx.strokeStyle = withAlpha(p, 1);
ctx.lineWidth = lineWidth;
ctx.lineCap = 'round';
ctx.stroke();
"""
        case .solid:
            cycleFormula = "2.0"
            drawBody = """
ctx.beginPath();
ctx.arc(cx, cy, ringRadius, 0, Math.PI * 2);
ctx.strokeStyle = withAlpha(p, 1);
ctx.lineWidth = lineWidth;
ctx.lineCap = 'round';
ctx.stroke();
"""
        case .off, .notApplicable:
            cycleFormula = "2.0"
            drawBody = """
ctx.beginPath();
ctx.arc(cx, cy, ringRadius, 0, Math.PI * 2);
ctx.strokeStyle = 'rgba(255,255,255,0.06)';
ctx.lineWidth = lineWidth;
ctx.lineCap = 'round';
ctx.stroke();
"""
        case .earConOnly:
            cycleFormula = "2.0"
            drawBody = """
ctx.beginPath();
ctx.arc(cx, cy, ringRadius, 0, Math.PI * 2);
ctx.strokeStyle = 'rgba(255,255,255,0.08)';
ctx.lineWidth = lineWidth;
ctx.stroke();
// No LED animation for this cue — overlay your own "speaker" icon in
// HTML/CSS on top of this canvas.
"""
        case .flash:
            cycleFormula = "(1 / config.speed) * 2"
            drawBody = """
const period = 1 / config.speed;
const on = (t % period) < period / 2;
ctx.beginPath();
ctx.arc(cx, cy, ringRadius, 0, Math.PI * 2);
ctx.strokeStyle = withAlpha(p, on ? 1 : 0.05);
ctx.lineWidth = lineWidth;
ctx.lineCap = 'round';
ctx.stroke();
"""
        case .quickFlash:
            cycleFormula = "Math.max(config.flashCount, 1) * 0.14 * 2 + 0.8"
            drawBody = """
const single = 0.14;
const flashWindow = Math.max(config.flashCount, 1) * single * 2;
const on = t < flashWindow ? (t % (single * 2)) < single : false;
ctx.beginPath();
ctx.arc(cx, cy, ringRadius, 0, Math.PI * 2);
ctx.strokeStyle = withAlpha(p, on ? 1 : 0.05);
ctx.lineWidth = lineWidth;
ctx.lineCap = 'round';
ctx.stroke();
"""
        case .ripple:
            cycleFormula = "(1.1 / config.speed) + 0.2"
            drawBody = """
const progress = (t / cycle) % 1;
for (let i = 0; i < 2; i++) {
  const rippleOffset = i * 0.5;
  const raw = (progress + rippleOffset) % 1;
  const eased = applyEasing(raw, config.easing, config.springBounce);
  const rippleColor = i % 2 === 0 ? p : s;
  ctx.beginPath();
  ctx.arc(cx, cy, ringRadius * (0.55 + 0.55 * eased), 0, Math.PI * 2);
  ctx.strokeStyle = withAlpha(rippleColor, 1 - eased);
  ctx.lineWidth = lineWidth * 0.6;
  ctx.stroke();
}
ctx.beginPath();
ctx.arc(cx, cy, ringRadius, 0, Math.PI * 2);
ctx.strokeStyle = withAlpha(p, 0.15);
ctx.lineWidth = lineWidth * 0.4;
ctx.stroke();
"""
        case .spin:
            cycleFormula = "1 / config.speed"
            drawBody = """
const revolutions = t * config.speed;
const eased = applyEasing(revolutions % 1);
const angle = (Math.floor(revolutions) + eased) * 2 * Math.PI;
ctx.beginPath();
ctx.arc(cx, cy, radius, 0, 2 * Math.PI);
ctx.strokeStyle = withAlpha(primary(t), 0.12);
ctx.lineWidth = lineWidth;
ctx.stroke();
ctx.beginPath();
ctx.arc(cx, cy, radius, angle - Math.PI / 2, angle - Math.PI / 2 + 0.28 * 2 * Math.PI);
ctx.strokeStyle = primary(t);
ctx.lineWidth = lineWidth;
ctx.lineCap = 'round';
ctx.stroke();
"""
        case .pulseAccelerate:
            cycleFormula = "2.2"
            drawBody = """
const local = t % 2.2;
const rate = 1.5 + (local / 2.2) * 8;
const value = (Math.sin(local * rate * 2 * Math.PI) + 1) / 2;
ctx.beginPath();
ctx.arc(cx, cy, radius, 0, 2 * Math.PI);
ctx.strokeStyle = withAlpha(primary(t), 0.4 + 0.6 * value);
ctx.lineWidth = lineWidth * (0.7 + 0.5 * value);
ctx.lineCap = 'round';
ctx.stroke();
"""
        case .rainbow:
            cycleFormula = "1 / config.speed"
            drawBody = """
const hue = ((t * config.speed) % 1) * 360;
ctx.beginPath();
ctx.arc(cx, cy, radius, 0, 2 * Math.PI);
ctx.strokeStyle = `hsl(${hue}, 85%, 60%)`;
ctx.lineWidth = lineWidth;
ctx.lineCap = 'round';
ctx.stroke();
"""
        case .transitionToSolid:
            cycleFormula = "0.5 + config.holdSeconds + 0.5"
            drawBody = """
const rampIn = 0.5;
const holdEnd = rampIn + config.holdSeconds;
let opacity;
if (t < rampIn) opacity = t / rampIn;
else if (t < holdEnd) opacity = 1;
else opacity = 0.05;
ctx.beginPath();
ctx.arc(cx, cy, ringRadius, 0, Math.PI * 2);
ctx.strokeStyle = withAlpha(p, Math.max(opacity, 0.05));
ctx.lineWidth = lineWidth;
ctx.lineCap = 'round';
ctx.stroke();
"""
        case .spinThenSolidFade:
            cycleFormula = "(1.1 / config.speed) + config.holdSeconds + config.fadeOutSeconds + 0.6"
            drawBody = """
const spinDuration = 1.1 / config.speed;
const holdEnd = spinDuration + config.holdSeconds;
if (t < spinDuration) {
  const head = t / spinDuration;
  const easedHead = applyEasing(head, config.easing, config.springBounce);
  ctx.beginPath();
  ctx.arc(cx, cy, ringRadius, 0, Math.PI * 2);
  ctx.strokeStyle = withAlpha(p, 0.12);
  ctx.lineWidth = lineWidth;
  ctx.stroke();
  const start = easedHead * Math.PI * 2 * 3;
  ctx.beginPath();
  ctx.arc(cx, cy, ringRadius, start, start + Math.PI * 2 * 0.28);
  ctx.strokeStyle = withAlpha(p, 1);
  ctx.lineWidth = lineWidth;
  ctx.lineCap = 'round';
  ctx.stroke();
} else if (t < holdEnd) {
  ctx.beginPath();
  ctx.arc(cx, cy, ringRadius, 0, Math.PI * 2);
  ctx.strokeStyle = withAlpha(p, 1);
  ctx.lineWidth = lineWidth;
  ctx.lineCap = 'round';
  ctx.stroke();
} else {
  const fadeProgress = config.fadeOutSeconds > 0 ? (t - holdEnd) / config.fadeOutSeconds : 1;
  ctx.beginPath();
  ctx.arc(cx, cy, ringRadius, 0, Math.PI * 2);
  ctx.strokeStyle = withAlpha(p, Math.max(1 - fadeProgress, 0.05));
  ctx.lineWidth = lineWidth;
  ctx.lineCap = 'round';
  ctx.stroke();
}
"""
        case .pulseAccelerateThenSolidFade:
            cycleFormula = "2.2 + config.holdSeconds + config.fadeOutSeconds + 0.6"
            drawBody = """
const pulseDuration = 2.2;
const holdEnd = pulseDuration + config.holdSeconds;
if (t < pulseDuration) {
  const progress = t / pulseDuration;
  const rate = 1.5 + progress * 8;
  const value = (Math.sin(t * rate * Math.PI * 2) + 1) / 2;
  ctx.beginPath();
  ctx.arc(cx, cy, ringRadius, 0, Math.PI * 2);
  ctx.strokeStyle = withAlpha(p, 0.4 + 0.6 * value);
  ctx.lineWidth = lineWidth * (0.7 + 0.5 * value);
  ctx.lineCap = 'round';
  ctx.stroke();
} else if (t < holdEnd) {
  ctx.beginPath();
  ctx.arc(cx, cy, ringRadius, 0, Math.PI * 2);
  ctx.strokeStyle = withAlpha(p, 1);
  ctx.lineWidth = lineWidth;
  ctx.lineCap = 'round';
  ctx.stroke();
} else {
  const fadeProgress = config.fadeOutSeconds > 0 ? (t - holdEnd) / config.fadeOutSeconds : 1;
  ctx.beginPath();
  ctx.arc(cx, cy, ringRadius, 0, Math.PI * 2);
  ctx.strokeStyle = withAlpha(p, Math.max(1 - fadeProgress, 0.05));
  ctx.lineWidth = lineWidth;
  ctx.lineCap = 'round';
  ctx.stroke();
}
"""
        case .rainbowThenWhiteFade:
            cycleFormula = "(1.5 / config.speed) + config.holdSeconds + config.fadeOutSeconds + 0.6"
            drawBody = """
const spinDuration = 1.5 / config.speed;
const holdEnd = spinDuration + config.holdSeconds;
if (t < spinDuration) {
  const hue = (t / spinDuration) * 360;
  const rainbow = hsvToRgb(hue, 0.85, 1);
  ctx.beginPath();
  ctx.arc(cx, cy, ringRadius, 0, Math.PI * 2);
  ctx.strokeStyle = withAlpha(rainbow, 1);
  ctx.lineWidth = lineWidth;
  ctx.lineCap = 'round';
  ctx.stroke();
} else if (t < holdEnd) {
  ctx.beginPath();
  ctx.arc(cx, cy, ringRadius, 0, Math.PI * 2);
  ctx.strokeStyle = 'rgba(255,255,255,1)';
  ctx.lineWidth = lineWidth;
  ctx.lineCap = 'round';
  ctx.stroke();
} else {
  const fadeProgress = config.fadeOutSeconds > 0 ? (t - holdEnd) / config.fadeOutSeconds : 1;
  ctx.beginPath();
  ctx.arc(cx, cy, ringRadius, 0, Math.PI * 2);
  ctx.strokeStyle = 'rgba(255,255,255,' + Math.max(1 - fadeProgress, 0.05) + ')';
  ctx.lineWidth = lineWidth;
  ctx.lineCap = 'round';
  ctx.stroke();
}
"""
        case .voiceAssistantColor:
            cycleFormula = "2.4 / config.speed"
            drawBody = """
const voicePhase = t * config.speed * Math.PI * 2;
ctx.beginPath();
ctx.arc(cx, cy, ringRadius, 0, Math.PI * 2);
ctx.strokeStyle = conicGradient(cx, cy, p, s);
ctx.lineWidth = lineWidth;
ctx.lineCap = 'round';
ctx.save();
ctx.translate(cx, cy);
ctx.rotate(voicePhase);
ctx.translate(-cx, -cy);
ctx.stroke();
ctx.restore();
"""
        case .custom:
            cycleFormula = "2.0"
            drawBody = """
ctx.beginPath();
ctx.arc(cx, cy, ringRadius, 0, Math.PI * 2);
ctx.strokeStyle = withAlpha(p, 0.5);
ctx.lineWidth = lineWidth;
ctx.lineCap = 'round';
ctx.stroke();
"""
        }

        return """
<!-- Generated by RingAnimator -->
<!-- Cue: \(cue.name) (\([cue.category, cue.subcategory].compactMap { $0 }.joined(separator: " · "))) -->
<!-- Style: \(parameters.style.displayName) -->
<!--
  Spec sheet reference: \(cue.specText)

  Self-contained cue for the web: a <canvas> driven by requestAnimationFrame.
  Drop this file's <div>/<style>/<script> wherever the cue should live, or
  lift the JS into your own animation loop. Needs a browser with
  conic-gradient canvas support (Chrome 90+, Safari 16.4+, Firefox 113+)
  if this cue uses the Voice Assistant Color style.
-->
<div id="cue-\(idSuffix)" style="width: 160px; height: 160px;">
  <canvas id="cue-\(idSuffix)-canvas"></canvas>
</div>

<style>
  #cue-\(idSuffix) { position: relative; }
  #cue-\(idSuffix)-canvas { width: 100%; height: 100%; display: block; }
</style>

<script>
(function () {
  const config = {
    diameter: 160,
    lineWidth: 12,
    speed: \(max(parameters.speed, 0.05)),
    flashCount: \(parameters.flashCount),
    holdSeconds: \(parameters.holdSeconds),
    fadeOutSeconds: \(parameters.fadeOutSeconds),
    primaryColor: '\(parameters.primaryColorHex)',
    secondaryColor: '\(parameters.secondaryColorHex)',

    // Motion effects
    easing: '\(jsEasingCaseName(parameters.easingStyle))',
    springBounce: \(parameters.springBounce),
    scalePulseEnabled: \(parameters.scalePulseEnabled),
    scalePulseAmount: \(parameters.scalePulseAmount),
    scalePulseSpeed: \(parameters.scalePulseSpeed),
    hueShiftEnabled: \(parameters.hueShiftEnabled),
    hueShiftSpeed: \(parameters.hueShiftSpeed),
    blurRadius: \(parameters.blurRadius),
    blendMode: '\(jsCompositeOperation(parameters.blendMode))',
    chromaticAberrationEnabled: \(parameters.chromaticAberrationEnabled),
    chromaticAberrationAmount: \(parameters.chromaticAberrationAmount),
    particlesEnabled: \(parameters.particlesEnabled),
    particleEmitterShape: '\(parameters.particleEmitterShape.rawValue)',
    particleEmitterMode: '\(swiftEmitterModeCaseName(parameters.particleEmitterMode))',
    particleEmitterSizeMultiplier: \(parameters.particleEmitterSizeMultiplier),
    particleRenderMode: '\(parameters.particleRenderMode.rawValue)',
    particleBirthRate: \(parameters.particleBirthRate),
    particleLifetime: \(parameters.particleLifetime),
    particleLifetimeRange: \(parameters.particleLifetimeRange),
    particleVelocity: \(parameters.particleVelocity),
    particleVelocityRange: \(parameters.particleVelocityRange),
    particleEmissionLongitude: \(parameters.particleEmissionLongitude),
    particleEmissionSpread: \(parameters.particleEmissionSpread),
    particleXAcceleration: \(parameters.particleXAcceleration),
    particleYAcceleration: \(parameters.particleYAcceleration),
    particleSpin: \(parameters.particleSpin),
    particleSpinRange: \(parameters.particleSpinRange),
    particleScale: \(parameters.particleScale),
    particleScaleRange: \(parameters.particleScaleRange),
    particlePulseEnabled: \(parameters.particlePulseEnabled),
    particlePulsePeriod: \(parameters.particlePulsePeriod),
    particleBlurRadius: \(parameters.particleBlurRadius)
  };

  const container = document.getElementById('cue-\(idSuffix)');
  const canvas = document.getElementById('cue-\(idSuffix)-canvas');
  const ctx = canvas.getContext('2d');
  const dpr = window.devicePixelRatio || 1;
  canvas.width = config.diameter * dpr;
  canvas.height = config.diameter * dpr;
  ctx.scale(dpr, dpr);

  // Only needed for chromatic aberration: a reusable offscreen canvas each
  // color-channel pass draws into before being tinted and composited back
  // onto the main canvas — see the `chromaticAberrationEnabled` branch in
  // frame() below.
  const offCanvas = document.createElement('canvas');
  offCanvas.width = canvas.width;
  offCanvas.height = canvas.height;
  const offCtx = offCanvas.getContext('2d');
  offCtx.scale(dpr, dpr);

  function applyEasing(t, style, bounce) {
    switch (style) {
      case 'linear': return t;
      case 'easeIn': return t * t;
      case 'easeOut': return 1 - (1 - t) * (1 - t);
      case 'easeInOut': return t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
      case 'spring': {
        const decay = Math.exp(-6 * t);
        return t + bounce * decay * Math.sin(t * Math.PI * 6);
      }
      default: return t;
    }
  }

  function hexToRgb(hex) {
    const clean = hex.replace('#', '');
    const num = parseInt(clean, 16);
    return { r: (num >> 16) & 255, g: (num >> 8) & 255, b: num & 255 };
  }

  function hsvToRgb(h, s, v) {
    const c = v * s;
    const x = c * (1 - Math.abs(((h / 60) % 2) - 1));
    const m = v - c;
    let r = 0, g = 0, b = 0;
    if (h < 60) { r = c; g = x; b = 0; }
    else if (h < 120) { r = x; g = c; b = 0; }
    else if (h < 180) { r = 0; g = c; b = x; }
    else if (h < 240) { r = 0; g = x; b = c; }
    else if (h < 300) { r = x; g = 0; b = c; }
    else { r = c; g = 0; b = x; }
    return { r: Math.round((r + m) * 255), g: Math.round((g + m) * 255), b: Math.round((b + m) * 255) };
  }

  function withAlpha(rgb, alpha) {
    return 'rgba(' + rgb.r + ',' + rgb.g + ',' + rgb.b + ',' + alpha + ')';
  }

  function colors(elapsed) {
    if (!config.hueShiftEnabled) {
      return { p: hexToRgb(config.primaryColor), s: hexToRgb(config.secondaryColor) };
    }
    const raw = (elapsed * config.hueShiftSpeed) % 1;
    const hue1 = ((raw < 0 ? raw + 1 : raw)) * 360;
    const hue2 = (hue1 + 180) % 360;
    return { p: hsvToRgb(hue1, 0.85, 1), s: hsvToRgb(hue2, 0.85, 1) };
  }

  // Same hue-shift math as `colors(elapsed)` above, just keyed on the
  // pattern's own looping `t` instead of raw elapsed time — matches the
  // SwiftUI/Compose exports, where the visible ring color loops with the
  // pattern but particles drift on continuous time.
  function hueColorAt(t, offset) {
    const raw = (t * config.hueShiftSpeed) % 1;
    const hue = (((raw < 0 ? raw + 1 : raw) + offset) % 1) * 360;
    return hsvToRgb(hue, 0.85, 1);
  }

  function primary(t) {
    return config.hueShiftEnabled ? hueColorAt(t, 0) : hexToRgb(config.primaryColor);
  }

  function secondary(t) {
    return config.hueShiftEnabled ? hueColorAt(t, 0.5) : hexToRgb(config.secondaryColor);
  }

  function conicGradient(cx, cy, p, s) {
    if (ctx.createConicGradient) {
      const grad = ctx.createConicGradient(0, cx, cy);
      grad.addColorStop(0, withAlpha(p, 1));
      grad.addColorStop(0.5, withAlpha(s, 1));
      grad.addColorStop(1, withAlpha(p, 1));
      return grad;
    }
    // Fallback for older browsers: flat primary color.
    return withAlpha(p, 1);
  }

\(jsParticlesFunctions())

  function frame(now) {
    const elapsed = now / 1000;
    const cycle = Math.max(\(cycleFormula), 0.2);
    const t = elapsed % cycle;
    const breathing = config.scalePulseEnabled
      ? 1 + config.scalePulseAmount * Math.sin(elapsed * config.scalePulseSpeed * 2 * Math.PI)
      : 1;

    const cx = config.diameter / 2;
    const cy = config.diameter / 2;
    const lineWidth = config.lineWidth;
    const ringRadius = config.diameter / 2 - lineWidth / 2 - 4;
    const p = primary(t);
    const s = secondary(t);

    ctx.clearRect(0, 0, config.diameter, config.diameter);
    ctx.save();
    ctx.filter = config.blurRadius > 0 ? 'blur(' + config.blurRadius + 'px)' : 'none';
    ctx.globalCompositeOperation = config.blendMode;

    ctx.translate(cx, cy);
    ctx.scale(breathing, breathing);
    ctx.translate(-cx, -cy);

    // The shape's draw code itself never references `ctx` beyond this
    // function's own parameter — wrapping it lets the exact same code draw
    // onto either the main canvas or an offscreen one for the chromatic
    // aberration passes below, with zero duplication.
    function drawShape(ctx) {
\(indent(drawBody, by: 6))
    }

    if (config.chromaticAberrationEnabled) {
      const offsetPx = config.chromaticAberrationAmount;
      const passes = [
        { color: 'rgb(255,0,0)', dx: -offsetPx, dy: offsetPx * 0.3 },
        { color: 'rgb(0,255,0)', dx: 0, dy: -offsetPx * 0.5 },
        { color: 'rgb(0,0,255)', dx: offsetPx, dy: offsetPx * 0.3 }
      ];
      for (const pass of passes) {
        offCtx.clearRect(0, 0, config.diameter, config.diameter);
        offCtx.save();
        offCtx.translate(cx, cy);
        offCtx.scale(breathing, breathing);
        offCtx.translate(-cx, -cy);
        drawShape(offCtx);
        offCtx.restore();
        // Isolate to one color channel (componentwise RGB multiply).
        offCtx.globalCompositeOperation = 'multiply';
        offCtx.fillStyle = pass.color;
        offCtx.fillRect(0, 0, config.diameter, config.diameter);
        offCtx.globalCompositeOperation = 'source-over';
        // Composite that channel back, offset and additively (screen)
        // blended — this is what recombines the 3 passes into the
        // exaggerated RGB-split look, Siri-"wavelengths"-style.
        ctx.globalCompositeOperation = 'screen';
        ctx.drawImage(offCanvas, pass.dx, pass.dy, config.diameter, config.diameter);
      }
      ctx.globalCompositeOperation = config.blendMode;
    } else {
      drawShape(ctx);
    }

    if (config.particlesEnabled) {
      const particleColors = colors(elapsed);
      drawParticles(elapsed, cx, cy, ringRadius, particleColors.p, particleColors.s);
    }

    ctx.restore();
    requestAnimationFrame(frame);
  }

  requestAnimationFrame(frame);
})();
</script>
"""
    }
}
