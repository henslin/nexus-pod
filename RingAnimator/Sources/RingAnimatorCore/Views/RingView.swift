import SwiftUI

/// The "AI is thinking" ring. Renders as a continuously-updating gradient
/// stroke so it matches a Siri/Apple-Intelligence-style glowing ring rather
/// than a ring made of discrete dots.
///
/// Layered on top of the four base animation types is a set of independent
/// effects: a per-cycle easing/spring curve, a breathing scale pulse, a
/// hue-shifting color cycle, blur, blend mode, a deterministic particle
/// layer, a hold/fade playback envelope (so you can preview it as a
/// one-shot cue instead of an infinite loop), and live voice reactivity —
/// any of which can combine with any animation type. The "background image"
/// context feature lives one level up, in the design tool's own large
/// preview (`ContentView.PreviewTab`) rather than here — it needs to fill
/// a whole preview viewport, not just this view's own (often tiny, e.g.
/// the 62pt tab bar pod) frame.
public struct RingView: View {
    @ObservedObject var config: RingConfig
    var diameter: CGFloat? = nil
    /// When set, renders one deterministic frame at exactly this elapsed
    /// time instead of driving off `TimelineView(.animation)`'s real
    /// wall-clock date — used by `AnimationExporter` to render a GIF/movie
    /// frame by frame. `easedPhase(elapsed:)` and everything downstream of
    /// it are pure functions of `elapsed`, so substituting `frameIndex /
    /// fps` here for real time reproduces an exact, repeatable frame every
    /// time (unlike the particle layer, which is real `CAEmitterLayer`
    /// physics `AnimationExporter` disables rather than trying to seek).
    var overrideElapsed: Double? = nil
    @StateObject private var audioMonitor = AudioLevelMonitor()

    // The size every absolute value on `RingConfig` (line width, glow
    // radius, particle size, ...) was tuned against — the tab bar's ring
    // pod. Rendering at any other `diameter` scales those values by
    // `size / referenceDiameter`, so bigger previews read as a proper
    // magnified version of the pod (thicker stroke, bigger glow, bigger
    // particles, all in the same proportion) instead of the same fixed-
    // width stroke stretched around a wider circle.
    private let referenceDiameter: CGFloat = 34

    public init(config: RingConfig, diameter: CGFloat? = nil, overrideElapsed: Double? = nil) {
        self.config = config
        self.diameter = diameter
        self.overrideElapsed = overrideElapsed
    }

    public var body: some View {
        Group {
            if let style = effectivePatternStyle {
                patternStyleBody(style: style)
            } else if let overrideElapsed {
                // Skips TimelineView entirely for a one-shot deterministic
                // render — TimelineView is built for continuous live
                // updates, not a single synchronous snapshot, so an export
                // renderer asking it for "the frame at time t" isn't a
                // scenario it's designed for.
                continuousAnimationContent(elapsed: overrideElapsed)
            } else {
                continuousAnimationBody
            }
        }
        .onAppear {
            // Skip the local mic tap entirely if ElevenLabs is already
            // connected — `SpeechToTextService` (see
            // `RingConfig.voiceConversation`) runs its own separate mic
            // tap for transcription, and this one's `.level` would just
            // be ignored anyway (see the ternary above). This check only
            // runs at appear/toggle time, not continuously — if you
            // disconnect from ElevenLabs later while Voice reactive stays
            // on, this one won't retroactively start; toggle Voice
            // reactive off and back on to pick the mic back up.
            if config.voiceReactiveEnabled && config.elevenLabs.connectionState != .connected {
                audioMonitor.start()
            }
        }
        .onDisappear {
            audioMonitor.stop()
        }
        .onChange(of: config.voiceReactiveEnabled) { _, enabled in
            if enabled && config.elevenLabs.connectionState != .connected {
                audioMonitor.start()
            } else {
                audioMonitor.stop()
            }
        }
    }

    /// `config.patternStyle`, but treating `.continuousAnimation` the same
    /// as `nil` — that case just means "use `animationType` below", i.e.
    /// exactly what `nil` already means, so there's no separate behavior to
    /// give it here. `ControlsView`'s picker for this leaves it out
    /// entirely for the same reason; this guard just means nothing breaks
    /// if it ends up set some other way (e.g. hand-edited state restore).
    private var effectivePatternStyle: LEDPatternStyle? {
        guard let style = config.patternStyle, style != .continuousAnimation else { return nil }
        return style
    }

    /// One of the Cue Library's canned Ziris spec-sheet behaviors, rendered
    /// by handing an equivalent `LEDCueParameters` to `LEDCuePreviewView`
    /// rather than reimplementing any of those patterns a second time here
    /// — the mirror image of how `LEDCuePreviewView` itself renders
    /// `.continuousAnimation` by handing an equivalent `RingConfig` to this
    /// same `RingView`. See `cueParameters(style:scale:)`.
    private func patternStyleBody(style: LEDPatternStyle) -> some View {
        GeometryReader { geo in
            let size = diameter ?? min(geo.size.width, geo.size.height)
            let scale = size / referenceDiameter
            LEDCuePreviewView(parameters: cueParameters(style: style, scale: scale), diameter: size, lineWidth: lw(scale), overrideElapsed: overrideElapsed)
                .frame(width: geo.size.width, height: geo.size.height)
                // Same reasoning as the `.clipShape(Circle())` on the
                // continuous-animation path below — keeps glow/particles/
                // blur contained to the pod's own round footprint.
                .clipShape(Circle())
        }
    }

    /// Builds the `LEDCueParameters` `patternStyleBody` above hands to
    /// `LEDCuePreviewView` — every field `LEDCuePreviewView`/`RingView`
    /// share gets copied straight across; particle/pixel-sized fields that
    /// `RingView`'s own native path scales by `size / referenceDiameter`
    /// (see the doc comment on that constant) get the same treatment here,
    /// since `LEDCuePreviewView` otherwise takes them as absolute point
    /// values tuned for its own typical ~120-160pt preview size.
    private func cueParameters(style: LEDPatternStyle, scale: CGFloat) -> LEDCueParameters {
        LEDCueParameters(
            style: style,
            primaryColorHex: config.primaryColor.hexString,
            secondaryColorHex: config.secondaryColor.hexString,
            speed: config.speed,
            flashCount: config.flashCount,
            holdSeconds: config.holdSeconds,
            fadeOutSeconds: config.fadeOutSeconds,
            loops: config.loops,
            animationType: config.animationType,
            lineWidth: Double(lw(scale)),
            trailFraction: config.trailFraction,
            chasingFillStyle: config.chasingFillStyle,
            diodeCount: config.diodeCount,
            easingStyle: config.easingStyle,
            springBounce: config.springBounce,
            scalePulseEnabled: config.scalePulseEnabled,
            scalePulseAmount: config.scalePulseAmount,
            scalePulseSpeed: config.scalePulseSpeed,
            hueShiftEnabled: config.hueShiftEnabled,
            hueShiftSpeed: config.hueShiftSpeed,
            blurRadius: config.blurRadius * Double(scale),
            blendMode: config.blendMode,
            chromaticAberrationEnabled: config.chromaticAberrationEnabled,
            chromaticAberrationAmount: config.chromaticAberrationAmount * Double(scale),
            glowEnabled: config.glowEnabled,
            glowRadius: config.glowRadius * Double(scale),
            vibrancyEnabled: config.vibrancyEnabled,
            vibrancyAmount: config.vibrancyAmount,
            particlesEnabled: config.particlesEnabled,
            particleEmitterShape: config.particleEmitterShape,
            particleEmitterMode: config.particleEmitterMode,
            particleEmitterSizeMultiplier: config.particleEmitterSizeMultiplier,
            particleRenderMode: config.particleRenderMode,
            particleBirthRate: config.particleBirthRate,
            particleLifetime: config.particleLifetime,
            particleLifetimeRange: config.particleLifetimeRange,
            particleVelocity: config.particleVelocity * Double(scale),
            particleVelocityRange: config.particleVelocityRange * Double(scale),
            particleEmissionLongitude: config.particleEmissionLongitude,
            particleEmissionSpread: config.particleEmissionSpread,
            particleXAcceleration: config.particleXAcceleration * Double(scale),
            particleYAcceleration: config.particleYAcceleration * Double(scale),
            particleSpin: config.particleSpin,
            particleSpinRange: config.particleSpinRange,
            particleScale: config.particleScale * Double(scale),
            particleScaleRange: config.particleScaleRange * Double(scale),
            particlePulseEnabled: config.particlePulseEnabled,
            particlePulsePeriod: config.particlePulsePeriod,
            particleBlurRadius: config.particleBlurRadius * Double(scale)
        )
    }

    /// The original continuous-animation rendering path — `animationType`'s
    /// 11 variants, unchanged in substance from before `patternStyle`
    /// existed.
    private var continuousAnimationBody: some View {
        TimelineView(.animation) { timeline in
            continuousAnimationContent(elapsed: timeline.date.timeIntervalSinceReferenceDate)
        }
    }

    /// The actual per-frame content, factored out of `continuousAnimationBody`
    /// so `AnimationExporter` (via `overrideElapsed` in `body` above) can
    /// call it directly with a synthetic elapsed time, bypassing
    /// `TimelineView` entirely for a one-shot deterministic snapshot.
    @ViewBuilder
    private func continuousAnimationContent(elapsed: Double) -> some View {
        let phase = easedPhase(elapsed: elapsed)
        // Prefer the connected ElevenLabs assistant's live speech level
        // over the local mic when both are available — see
        // `RingConfig.voiceReactiveEnabled`'s doc comment. Read fresh
        // every frame here rather than relying on Combine publishing,
        // since `TimelineView(.animation)` already re-invokes this
        // closure ~60x/second regardless.
        //
        // Written as a single ternary expression rather than an
        // if/else statement deliberately — this is a `@ViewBuilder`
        // function, which transforms *any* if/else statement in its
        // body via `buildEither`, even ones that only compute a plain
        // value like this. That transform expects each branch to
        // build a `View`, so a plain assignment inside if/else here
        // fails to type-check with "Generic parameter 'Content' could
        // not be inferred." A ternary is just an expression, not a
        // statement, so the builder never touches it.
        let voiceLevel: Double = !config.voiceReactiveEnabled
            ? 0
            : (config.elevenLabs.connectionState == .connected
                ? config.elevenLabs.level * config.voiceReactiveSensitivity
                : audioMonitor.level * config.voiceReactiveSensitivity)
        let breathing = (config.scalePulseEnabled
            ? 1 + config.scalePulseAmount * sin(elapsed * config.scalePulseSpeed * 2 * .pi)
            : 1) + voiceLevel * 0.25
        let envelopeOpacity = sequenceEnvelopeOpacity(elapsed: elapsed)

        GeometryReader { geo in
            let size = diameter ?? min(geo.size.width, geo.size.height)
            let scale = size / referenceDiameter
            // The container SwiftUI actually gave this view — usually
            // bigger than `size` itself (the tab bar pod is a 34pt ring
            // inside a 62pt frame; the large preview matches that same
            // ratio — see ContentView's `largePreview`). Particles get
            // that whole container to drift and fade in, instead of
            // being clipped the instant they cross the ring's own tight
            // bounding square.
            let particleFieldSize = min(geo.size.width, geo.size.height)

            ZStack {
                ringContent(phase: phase, elapsed: elapsed, voiceLevel: voiceLevel, size: size, scale: scale, particleFieldSize: particleFieldSize)
                    .scaleEffect(breathing)
                    .blur(radius: config.blurRadius * scale)
                    .compositingGroup()
                    // Saturation/contrast/brightness are Core Image
                    // filters that need the ring flattened to one image
                    // first (`.compositingGroup()` above) rather than
                    // applied per-shape — otherwise overlapping
                    // strokes/particles would each get boosted
                    // independently and the overlaps would blow out.
                    // Applied before `.blendMode` so the blend itself
                    // works with the already-punchier colors.
                    .saturation(vibrancyMultiplier)
                    .contrast(1 + (vibrancyMultiplier - 1) * 0.35)
                    .brightness((vibrancyMultiplier - 1) * 0.05)
                    .blendMode(config.blendMode.swiftUIBlendMode)
                    .opacity(envelopeOpacity)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            // Both call sites (`TabBarPreview`'s 62pt ring pod and
            // `ContentView`'s large preview) size this view's container
            // to the same circular "pod" footprint the ring is meant to
            // read as sitting inside — but nothing was actually
            // enforcing that boundary. Particles (`particleFieldSize`
            // above deliberately gives them the *whole* container, not
            // just the ring's own tight square, so they have room to
            // drift) and each animation's glow `.shadow(...)` could
            // both bleed past the circle into the pod/large-preview's
            // corners. Clipping the fully-composited result to a circle
            // inscribed in the container keeps everything — particles,
            // glow, blur — contained to the same round silhouette the
            // Liquid Glass pod itself uses, instead of a stray square
            // haze poking out past the glass edge.
            .clipShape(Circle())
        }
    }

    @ViewBuilder
    private func ringContent(phase: Double, elapsed: Double, voiceLevel: Double, size: CGFloat, scale: CGFloat, particleFieldSize: CGFloat) -> some View {
        ZStack {
            // Particles sit behind the ring — like corona rays emanating
            // from underneath it, not floating in front. Backed by a real
            // CAEmitterLayer (see RingParticleEmitter.swift) rather than
            // hand-rolled SwiftUI shapes. Sized/clipped to the full
            // available container (`particleFieldSize`, usually bigger than
            // the ring's own `size`) rather than the ring's tight bounding
            // square, so particles have real room to drift and fade before
            // getting cut off.
            if config.particlesEnabled {
                let (particleP, particleS) = colors(elapsed: elapsed)
                let particleView = RingParticleEmitterView(
                    particlesEnabled: config.particlesEnabled,
                    emitterShape: config.particleEmitterShape,
                    emitterMode: config.particleEmitterMode,
                    emitterSizeMultiplier: config.particleEmitterSizeMultiplier,
                    renderMode: config.particleRenderMode,
                    birthRate: config.particleBirthRate,
                    lifetime: config.particleLifetime,
                    lifetimeRange: config.particleLifetimeRange,
                    velocity: config.particleVelocity * scale,
                    velocityRange: config.particleVelocityRange * scale,
                    emissionLongitude: config.particleEmissionLongitude,
                    emissionSpread: config.particleEmissionSpread,
                    xAcceleration: config.particleXAcceleration * scale,
                    yAcceleration: config.particleYAcceleration * scale,
                    spin: config.particleSpin,
                    spinRange: config.particleSpinRange,
                    particleScale: config.particleScale * scale,
                    scaleRange: config.particleScaleRange * scale,
                    pulseEnabled: config.particlePulseEnabled,
                    pulsePeriod: config.particlePulsePeriod,
                    blurRadius: config.particleBlurRadius * scale,
                    primaryColor: particleP,
                    secondaryColor: particleS,
                    size: particleFieldSize,
                    ringRadius: size / 2 - lw(scale) / 2
                )
                // Belt-and-suspenders on top of the in-place update in
                // RingParticleEmitterView: keying `.id()` to every particle
                // parameter forces SwiftUI to fully tear down and recreate
                // the underlying CAEmitterLayer/cells from scratch whenever
                // any of them change, instead of relying on Core Animation
                // to notice an in-place mutation.
                particleView
                    .id(particleView.parameterSignature)
                    .frame(width: particleFieldSize, height: particleFieldSize)
                    .clipped()
                    .allowsHitTesting(false)
            }
            aberratedContent(phase: phase, elapsed: elapsed, voiceLevel: voiceLevel, scale: scale)
                .frame(width: size, height: size)
        }
    }

    /// Wraps `content(...)` with the chromatic aberration effect when it's
    /// on — three copies of the exact same animated shape, each isolated to
    /// one color channel (`.colorMultiply` zeroes out the other two) and
    /// nudged apart, recombined with `.screen` (additive) blending. This is
    /// a universal post-process: it doesn't touch any of the 9 animation
    /// variant functions below, so every one of them gets the effect for
    /// free. Deliberately exaggerated by default — a stylized RGB-split
    /// look (think Siri's colorful "wavelengths"), not a subtle lens
    /// artifact.
    @ViewBuilder
    private func aberratedContent(phase: Double, elapsed: Double, voiceLevel: Double, scale: CGFloat) -> some View {
        if config.chromaticAberrationEnabled {
            let offset = CGFloat(config.chromaticAberrationAmount) * scale
            ZStack {
                content(phase: phase, elapsed: elapsed, voiceLevel: voiceLevel, scale: scale)
                    .colorMultiply(.red)
                    .blendMode(.screen)
                    .offset(x: -offset, y: offset * 0.3)
                content(phase: phase, elapsed: elapsed, voiceLevel: voiceLevel, scale: scale)
                    .colorMultiply(.green)
                    .blendMode(.screen)
                    .offset(x: 0, y: -offset * 0.5)
                content(phase: phase, elapsed: elapsed, voiceLevel: voiceLevel, scale: scale)
                    .colorMultiply(.blue)
                    .blendMode(.screen)
                    .offset(x: offset, y: offset * 0.3)
            }
            .compositingGroup()
        } else {
            content(phase: phase, elapsed: elapsed, voiceLevel: voiceLevel, scale: scale)
        }
    }

    @ViewBuilder
    private func content(phase: Double, elapsed: Double, voiceLevel: Double, scale: CGFloat) -> some View {
        switch config.animationType {
        case .wave:
            waveRing(phase: phase, elapsed: elapsed, voiceLevel: voiceLevel, scale: scale)
        case .chasing:
            chasingRing(phase: phase, elapsed: elapsed, voiceLevel: voiceLevel, scale: scale)
        case .alternating:
            alternatingRing(phase: phase, elapsed: elapsed, voiceLevel: voiceLevel, scale: scale)
        case .pulse:
            pulseRing(phase: phase, elapsed: elapsed, voiceLevel: voiceLevel, scale: scale)
        case .ripple:
            rippleRing(phase: phase, elapsed: elapsed, voiceLevel: voiceLevel, scale: scale)
        case .wobble:
            wobbleRing(phase: phase, elapsed: elapsed, voiceLevel: voiceLevel, scale: scale)
        case .equalizer:
            equalizerRing(phase: phase, elapsed: elapsed, voiceLevel: voiceLevel, scale: scale)
        case .dualChase:
            dualChaseRing(phase: phase, elapsed: elapsed, voiceLevel: voiceLevel, scale: scale)
        case .multiChase:
            multiChaseRing(phase: phase, elapsed: elapsed, voiceLevel: voiceLevel, scale: scale)
        case .sparkle:
            sparkleRing(phase: phase, elapsed: elapsed, voiceLevel: voiceLevel, scale: scale)
        case .aurora:
            auroraRing(phase: phase, elapsed: elapsed, voiceLevel: voiceLevel, scale: scale)
        case .liquidFill:
            liquidFillRing(phase: phase, elapsed: elapsed, voiceLevel: voiceLevel, scale: scale)
        }
    }

    // MARK: - Per-cycle easing

    /// Applies the configured timing curve to each rotation cycle while
    /// keeping the overall phase ever-increasing (so rotation stays
    /// perfectly continuous — see `MotionEasing` for why this never snaps).
    private func easedPhase(elapsed: Double) -> Double {
        let cycles = elapsed * config.speed
        let n = cycles.rounded(.down)
        let f = cycles - n
        let easedF = MotionEasing.apply(f, style: config.easingStyle, bounce: config.springBounce)
        return (n + easedF) * 2 * Double.pi
    }

    // MARK: - Playback envelope

    /// When `sequencePlaybackEnabled` is off, always fully visible (the
    /// original infinite-loop behavior). When on, ramps up over
    /// `fadeInSeconds`, holds at full opacity for `holdSeconds`, fades out
    /// over `fadeOutSeconds`, and either repeats forever (`loops == 0`) or
    /// plays that many times and stays faded.
    ///
    /// `fadeInSeconds` defaults to 0, which collapses the first branch below
    /// to a no-op and leaves this behaving exactly as it did before fade-in
    /// existed — worth keeping in mind, since every saved preset written
    /// before that field decodes with it at 0.
    private func sequenceEnvelopeOpacity(elapsed: Double) -> Double {
        guard config.sequencePlaybackEnabled else { return 1 }
        let fadeIn = max(config.fadeInSeconds, 0)
        let envelopeDuration = max(fadeIn + config.holdSeconds + config.fadeOutSeconds, 0.1)

        if config.loops > 0 {
            let totalDuration = envelopeDuration * Double(config.loops)
            if elapsed >= totalDuration { return 0 }
        }

        let t = elapsed.truncatingRemainder(dividingBy: envelopeDuration)
        if t < fadeIn {
            // Guarded division: `t < fadeIn` already implies `fadeIn > 0`,
            // so this branch can't divide by zero — but the `max` keeps it
            // safe against a denormal fadeIn slipping through.
            return min(t / max(fadeIn, 0.001), 1)
        }
        let heldUntil = fadeIn + config.holdSeconds
        if t < heldUntil {
            return 1
        }
        let fadeT = (t - heldUntil) / max(config.fadeOutSeconds, 0.001)
        return max(1 - fadeT, 0)
    }

    // MARK: - Colors

    /// Every configured color — `primaryColor`/`secondaryColor` plus
    /// whatever's in `additionalColors` — in order. The animation variants
    /// below read from this directly (cycling `all[i % all.count]` per
    /// element) when they render several discrete pieces, or through
    /// `colors(elapsed:)`'s first-two convenience when they only ever need
    /// a "main" color and a counterpart — either way, adding a 3rd/4th/...
    /// color via the Controls panel's "+ Add Color" changes what's
    /// actually rendered, not just what's stored.
    ///
    /// Hue-shift generalizes the old "two complementary hues 180° apart"
    /// behavior to N evenly-spaced hues around the color wheel (N being
    /// however many colors are configured) — the same rotating-hue idea,
    /// just one point per slot instead of hard-coding exactly 2.
    private func activeColors(elapsed: Double) -> [Color] {
        let configured = [config.primaryColor, config.secondaryColor] + config.additionalColors
        guard config.hueShiftEnabled else { return configured }
        let raw = (elapsed * config.hueShiftSpeed).truncatingRemainder(dividingBy: 1)
        let base = raw < 0 ? raw + 1 : raw
        let n = configured.count
        return (0..<n).map { i in
            let hue = (base + Double(i) / Double(n)).truncatingRemainder(dividingBy: 1)
            return Color(hue: hue, saturation: 0.85, brightness: 1)
        }
    }

    /// Convenience for variants that only ever need a "main" color and a
    /// counterpart (a glow tint, a track/background stroke, the two arcs
    /// in "Dual Chase") rather than cycling through every configured
    /// color — always `activeColors`' first two entries. Never runs out:
    /// Primary/Secondary are permanent slots, so there are always at least 2.
    private func colors(elapsed: Double) -> (primary: Color, secondary: Color) {
        let all = activeColors(elapsed: elapsed)
        return (all[0], all[1])
    }

    private func gradient(elapsed: Double) -> AngularGradient {
        let all = activeColors(elapsed: elapsed)
        // Closes the loop back to the first color so the sweep reads as
        // one continuous band with no hard seam — the same reason the old
        // 2-color version repeated `p` at both ends ([p, s, p]).
        return AngularGradient(colors: all + [all[0]], center: .center)
    }

    // MARK: - Shared pieces

    /// `1` when vibrancy is off — every call site below multiplies by this
    /// unconditionally rather than branching, so turning vibrancy off is
    /// exactly equivalent to `vibrancyAmount == 1`, not a separate code path
    /// that could drift out of sync with it.
    private var vibrancyMultiplier: Double {
        config.vibrancyEnabled ? config.vibrancyAmount : 1
    }

    /// `boost` (0...~) is the live voice-reactive contribution — widens the
    /// glow and nudges its opacity up without needing a separate code path.
    /// `scale` is `size / referenceDiameter` — the glow radius scales with
    /// it just like the stroke, so it stays proportional at any diameter.
    /// Vibrancy rides along at a gentler fraction than the saturation/
    /// contrast boost in `body` — a wider, slightly stronger halo reads as
    /// part of the same "pop," without the glow ballooning out of
    /// proportion with the ring itself at high vibrancy values.
    private func glow(_ view: some View, color: Color, boost: Double = 0, scale: CGFloat) -> some View {
        let vibrancyGlowBoost = 1 + (vibrancyMultiplier - 1) * 0.6
        let radius = config.glowEnabled ? CGFloat(config.glowRadius) * scale * (1 + boost) * CGFloat(vibrancyGlowBoost) : 0
        let opacity = config.glowEnabled ? min((0.7 + boost * 0.3) * vibrancyGlowBoost, 1) : 0
        return view.shadow(color: color.opacity(opacity), radius: radius)
    }

    private func lw(_ scale: CGFloat) -> CGFloat { CGFloat(config.lineWidth) * scale }

    // MARK: - Animation variants

    private func waveRing(phase: Double, elapsed: Double, voiceLevel: Double, scale: CGFloat) -> some View {
        let (p, _) = colors(elapsed: elapsed)
        return glow(
            Circle()
                .stroke(gradient(elapsed: elapsed), style: StrokeStyle(lineWidth: lw(scale), lineCap: .round))
                .rotationEffect(.radians(phase)),
            color: p,
            boost: voiceLevel,
            scale: scale
        )
    }

    private func chasingRing(phase: Double, elapsed: Double, voiceLevel: Double, scale: CGFloat) -> some View {
        let (p, s) = colors(elapsed: elapsed)
        return glow(
            ZStack {
                Circle()
                    .stroke(p.opacity(0.12), lineWidth: lw(scale))
                chasingArc(phase: phase, elapsed: elapsed, scale: scale)
            },
            color: s,
            boost: voiceLevel,
            scale: scale
        )
    }

    /// The trimmed, rotating arc at the heart of "Chasing" mode — split out
    /// from `chasingRing` so the two `ChasingFillStyle`s (structurally
    /// different `Circle().trim(...)` calls) can live behind one
    /// `@ViewBuilder` switch instead of needing two separate calls to
    /// `glow(_:)` (which would give `chasingRing` two different opaque
    /// return types — not allowed for a single `some View` function).
    ///
    /// `.trailingTail`: a constant-length arc, `.rotationEffect`-ed by the
    /// ever-increasing `head` angle — unchanged from the original behavior.
    ///
    /// `.drawUndraw`: the classic system-spinner move. `Circle().trim(from:
    /// 0, to:)` rotated by `phase` puts the trim's start at absolute angle
    /// `phase` and its end at `phase + length*2π` — both monotonically
    /// forward as `phase` climbs. Pulsing `length` with `sin(f * .pi)`
    /// (0 → `trailFraction` → 0 once per lap, `f` being the fractional
    /// progress through the current lap) makes the arc grow forward from a
    /// point, then have its trailing edge sweep forward to "catch" the
    /// leading edge and erase it — all in the same clockwise direction,
    /// never backtracking.
    @ViewBuilder
    private func chasingArc(phase: Double, elapsed: Double, scale: CGFloat) -> some View {
        switch config.chasingFillStyle {
        case .trailingTail:
            let head = phase / (2 * Double.pi)
            Circle()
                .trim(from: 0, to: config.trailFraction)
                .stroke(gradient(elapsed: elapsed), style: StrokeStyle(lineWidth: lw(scale), lineCap: .round))
                .rotationEffect(.radians(head * 2 * Double.pi))
        case .drawUndraw:
            let cycles = elapsed * config.speed
            let f = cycles - cycles.rounded(.down)
            let length = sin(f * Double.pi) * config.trailFraction
            Circle()
                .trim(from: 0, to: max(length, 0.0001)) // avoid a fully-empty trim, which some renderers draw as a full circle
                .stroke(gradient(elapsed: elapsed), style: StrokeStyle(lineWidth: lw(scale), lineCap: .round))
                .rotationEffect(.radians(phase))
        }
    }

    /// String-lights style: discrete diodes spaced evenly around the ring,
    /// alternating on/off in two interleaved groups (odds vs. evens) that
    /// swap back and forth, like a strand of fairy lights.
    private func alternatingRing(phase: Double, elapsed: Double, voiceLevel: Double, scale: CGFloat) -> some View {
        let blink = (sin(phase) + 1) / 2
        let count = max(Int(config.diodeCount.rounded()), 2)
        let all = activeColors(elapsed: elapsed)
        let diodeSize = lw(scale)
        return glow(
            GeometryReader { geo in
                let radius = min(geo.size.width, geo.size.height) / 2 - diodeSize / 2
                ZStack {
                    ForEach(0..<count, id: \.self) { i in
                        let angle = (Double(i) / Double(count)) * 2 * Double.pi - .pi / 2
                        // The on/off blink groups stay strict even/odd
                        // (unrelated to color count) — colors cycle
                        // through every configured slot independently, so
                        // more colors just means more distinct diodes,
                        // still swapping the same two blink groups back
                        // and forth.
                        let isEven = i.isMultiple(of: 2)
                        Circle()
                            .fill(all[i % all.count])
                            .frame(width: diodeSize, height: diodeSize)
                            .opacity(isEven ? blink : 1 - blink)
                            .position(
                                x: geo.size.width / 2 + cos(angle) * radius,
                                y: geo.size.height / 2 + sin(angle) * radius
                            )
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            },
            color: all[0],
            boost: voiceLevel,
            scale: scale
        )
    }

    private func pulseRing(phase: Double, elapsed: Double, voiceLevel: Double, scale: CGFloat) -> some View {
        let value = (sin(phase) + 1) / 2
        let (p, _) = colors(elapsed: elapsed)
        return glow(
            Circle()
                .stroke(gradient(elapsed: elapsed), style: StrokeStyle(lineWidth: lw(scale) * CGFloat(0.7 + 0.6 * value), lineCap: .round))
                .opacity(0.55 + 0.45 * value)
                .scaleEffect(0.94 + 0.06 * value),
            color: p,
            boost: voiceLevel,
            scale: scale
        )
    }

    /// Concentric rings expand outward from the track and fade — a sonar
    /// ping. Three waves are staggered evenly through the cycle (via a
    /// fixed offset per index) so a new one keeps emanating as the last
    /// fades out, instead of all pulsing in lockstep.
    private func rippleRing(phase: Double, elapsed: Double, voiceLevel: Double, scale: CGFloat) -> some View {
        let all = activeColors(elapsed: elapsed)
        let cycles = elapsed * config.speed
        let f = cycles - cycles.rounded(.down)
        let waveCount = 3
        return glow(
            ZStack {
                Circle()
                    .stroke(all[0].opacity(0.25), lineWidth: lw(scale))
                ForEach(0..<waveCount, id: \.self) { i in
                    let localT = (f + Double(i) / Double(waveCount)).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .stroke(
                            all[i % all.count].opacity((1 - localT) * 0.8),
                            lineWidth: lw(scale) * CGFloat(1 - localT * 0.5)
                        )
                        .scaleEffect(1 + localT * 0.6)
                }
            },
            color: all[0],
            boost: voiceLevel,
            scale: scale
        )
    }

    /// The ring's own radius undulates around its circumference instead of
    /// staying a perfect circle — two overlapping sine harmonics (3 and 5
    /// lobes) both driven by `phase`, sampled at 120 points into a closed
    /// `Path`. An organic, breathing-membrane look, closer to Apple's own
    /// Siri glow than a rigid stroke.
    private func wobbleRing(phase: Double, elapsed: Double, voiceLevel: Double, scale: CGFloat) -> some View {
        let (p, _) = colors(elapsed: elapsed)
        return glow(
            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                let baseRadius = size / 2 - lw(scale) / 2
                let amplitude = size * 0.035
                Path { path in
                    let steps = 120
                    for i in 0...steps {
                        let t = Double(i) / Double(steps)
                        let theta = t * 2 * Double.pi
                        let wobble = sin(theta * 3 + phase) + sin(theta * 5 - phase * 1.3) * 0.5
                        let radius = baseRadius + amplitude * CGFloat(wobble) / 1.5
                        let x = center.x + cos(theta) * radius
                        let y = center.y + sin(theta) * radius
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    path.closeSubpath()
                }
                .stroke(gradient(elapsed: elapsed), style: StrokeStyle(lineWidth: lw(scale), lineCap: .round, lineJoin: .round))
            },
            color: p,
            boost: voiceLevel,
            scale: scale
        )
    }

    /// The ring splits into `diodeCount` segments, each pulsing its own
    /// brightness/width on an independently-seeded rate — a VU-meter feel.
    /// Real voice input (`voiceLevel`, when reactive mode is on) adds
    /// straight on top of every segment's own pulse.
    private func equalizerRing(phase: Double, elapsed: Double, voiceLevel: Double, scale: CGFloat) -> some View {
        let count = max(Int(config.diodeCount.rounded()), 4)
        let all = activeColors(elapsed: elapsed)
        let segmentFraction = (1.0 / Double(count)) * 0.7
        return glow(
            ZStack {
                Circle().stroke(all[0].opacity(0.12), lineWidth: lw(scale))
                ForEach(0..<count, id: \.self) { i in
                    let seed = pseudoRandom(i)
                    let localPhase = elapsed * config.speed * 2 * Double.pi * (0.6 + seed * 0.8) + seed * 2 * Double.pi
                    let value = min((sin(localPhase) + 1) / 2 + voiceLevel * 0.4, 1)
                    let start = Double(i) / Double(count)
                    Circle()
                        .trim(from: start, to: start + segmentFraction)
                        .stroke(
                            all[i % all.count],
                            style: StrokeStyle(lineWidth: lw(scale) * CGFloat(0.3 + value * 0.7), lineCap: .round)
                        )
                        .opacity(0.5 + value * 0.5)
                }
            },
            color: all[0],
            boost: voiceLevel,
            scale: scale
        )
    }

    /// Two constant-length arcs (`trailFraction` each) chase in opposite
    /// directions — solid primary/secondary colors rather than the shared
    /// gradient, so the two stay visually distinct as they cross.
    /// Discrete diodes with one comet per configured color.
    ///
    /// The colors come from the Color section as-is — every configured
    /// color gets its own comet, evenly spaced around the ring and all
    /// travelling the same direction, so "three colors chasing each other"
    /// needs no separate count to set. That's the same
    /// `activeColors`-driven convention `alternating` and `sparkle`
    /// already follow.
    ///
    /// Each diode's brightness is the *maximum* over the comets rather
    /// than a sum: where two comets overlap the brighter one wins, instead
    /// of the overlap blowing out to white and reading as a third color
    /// that was never configured. The color drawn is whichever comet is
    /// brightest there, so a crossing reads as one passing in front of the
    /// other.
    private func multiChaseRing(phase: Double, elapsed: Double, voiceLevel: Double, scale: CGFloat) -> some View {
        let all = activeColors(elapsed: elapsed)
        let count = max(Int(config.diodeCount.rounded()), 2)
        let diodeSize = lw(scale)
        // Fraction of the ring each comet's tail covers. Guarded above
        // zero so a comet is never zero-length (which would light nothing
        // at all and look like the animation had stopped).
        let tail = max(config.trailFraction, 0.02)
        let head = phase / (2 * Double.pi)

        return glow(
            GeometryReader { geo in
                let radius = min(geo.size.width, geo.size.height) / 2 - diodeSize / 2
                ZStack {
                    ForEach(0..<count, id: \.self) { i in
                        let position = Double(i) / Double(count)
                        let lit = brightestComet(at: position, head: head, tail: tail, colorCount: all.count)
                        let angle = position * 2 * Double.pi - .pi / 2
                        Circle()
                            .fill(all[lit.colorIndex % all.count])
                            .frame(width: diodeSize, height: diodeSize)
                            .opacity(lit.brightness * blinkMultiplier(index: i, elapsed: elapsed))
                            .position(
                                x: geo.size.width / 2 + cos(angle) * radius,
                                y: geo.size.height / 2 + sin(angle) * radius
                            )
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            },
            color: all[0],
            boost: voiceLevel,
            scale: scale
        )
    }

    /// Which comet is brightest at a given point on the ring, and how
    /// bright. Comet `k` of `colorCount` sits `k / colorCount` of a lap
    /// behind the head, and fades linearly back along `tail`.
    private func brightestComet(
        at position: Double,
        head: Double,
        tail: Double,
        colorCount: Int
    ) -> (colorIndex: Int, brightness: Double) {
        var best = (colorIndex: 0, brightness: 0.0)
        for k in 0..<max(colorCount, 1) {
            let cometHead = head + Double(k) / Double(max(colorCount, 1))
            // Distance *behind* the comet head, wrapped into 0..<1 so the
            // comparison works across the seam at the top of the ring.
            var behind = (cometHead - position).truncatingRemainder(dividingBy: 1)
            if behind < 0 { behind += 1 }
            guard behind < tail else { continue }
            let brightness = 1 - (behind / tail)
            if brightness > best.brightness {
                best = (colorIndex: k, brightness: brightness)
            }
        }
        // Unlit diodes stay faintly visible, the same way `chasing` draws a
        // dim full-circle track behind its arc — otherwise the ring's shape
        // disappears wherever no comet currently is.
        return best.brightness > 0.06 ? best : (best.colorIndex, 0.06)
    }

    /// `BlinkPattern` as a 0...1 multiplier on a diode's brightness.
    private func blinkMultiplier(index: Int, elapsed: Double) -> Double {
        let cycle = elapsed * config.blinkRate
        switch config.blinkPattern {
        case .steady:
            return 1
        case .alternate:
            let swing = (sin(cycle * 2 * Double.pi) + 1) / 2
            return index.isMultiple(of: 2) ? swing : 1 - swing
        case .pulse:
            return 0.25 + 0.75 * (sin(cycle * 2 * Double.pi) + 1) / 2
        case .strobe:
            return cycle.truncatingRemainder(dividingBy: 1) < 0.5 ? 1 : 0.05
        }
    }

    private func dualChaseRing(phase: Double, elapsed: Double, voiceLevel: Double, scale: CGFloat) -> some View {
        let (p, s) = colors(elapsed: elapsed)
        return glow(
            ZStack {
                Circle()
                    .stroke(p.opacity(0.12), lineWidth: lw(scale))
                Circle()
                    .trim(from: 0, to: config.trailFraction)
                    .stroke(p, style: StrokeStyle(lineWidth: lw(scale), lineCap: .round))
                    .rotationEffect(.radians(phase))
                Circle()
                    .trim(from: 0, to: config.trailFraction)
                    .stroke(s, style: StrokeStyle(lineWidth: lw(scale), lineCap: .round))
                    .rotationEffect(.radians(-phase))
            },
            color: s,
            boost: voiceLevel,
            scale: scale
        )
    }

    /// `diodeCount` fixed points around the ring, each flashing bright then
    /// fading on its own pseudo-randomly-seeded rate and phase offset — a
    /// deterministic stand-in for "random" that stays reproducible frame to
    /// frame and identical across the SwiftUI/Compose/Web exports.
    private func sparkleRing(phase: Double, elapsed: Double, voiceLevel: Double, scale: CGFloat) -> some View {
        let count = max(Int(config.diodeCount.rounded()), 4)
        let all = activeColors(elapsed: elapsed)
        let dotSize = lw(scale)
        return glow(
            GeometryReader { geo in
                let radius = min(geo.size.width, geo.size.height) / 2 - dotSize / 2
                ZStack {
                    Circle().stroke(all[0].opacity(0.1), lineWidth: lw(scale) * 0.4)
                    ForEach(0..<count, id: \.self) { i in
                        let angle = (Double(i) / Double(count)) * 2 * Double.pi - .pi / 2
                        let seed = pseudoRandom(i)
                        let cycles = elapsed * config.speed * (0.5 + seed) + seed * 4
                        let f = cycles - cycles.rounded(.down)
                        // Bright for the first quarter of this point's own cycle, dim the rest.
                        let brightness = max(0, 1 - f * 4)
                        Circle()
                            .fill(all[i % all.count])
                            .frame(width: dotSize, height: dotSize)
                            .opacity(0.15 + brightness * 0.85 + voiceLevel * 0.2)
                            .scaleEffect(0.6 + brightness * 0.6)
                            .position(
                                x: geo.size.width / 2 + cos(angle) * radius,
                                y: geo.size.height / 2 + sin(angle) * radius
                            )
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            },
            color: all[0],
            boost: voiceLevel,
            scale: scale
        )
    }

    /// Soft, slow-drifting color bands sweep across the ring at their own
    /// independent (pseudo-randomly seeded) angular speeds and pulse their
    /// own opacity — closer to an aurora curtain than the uniform,
    /// whole-palette rotation of hue-shift, which shifts every pixel's
    /// color together instead of having separate bands drift past one
    /// another.
    private func auroraRing(phase: Double, elapsed: Double, voiceLevel: Double, scale: CGFloat) -> some View {
        let bandCount = 3
        let all = activeColors(elapsed: elapsed)
        return glow(
            ZStack {
                Circle().stroke(all[0].opacity(0.08), lineWidth: lw(scale) * 0.4)
                ForEach(0..<bandCount, id: \.self) { i in
                    let seed = pseudoRandom(i)
                    let bandSpeed = config.speed * (0.12 + seed * 0.22)
                    let bandPhase = elapsed * bandSpeed * 2 * Double.pi + seed * 2 * Double.pi
                    let bandLength = 0.22 + seed * 0.16
                    let pulse = 0.5 + 0.5 * sin(elapsed * (0.3 + seed * 0.4) + seed * 6)
                    Circle()
                        .trim(from: 0, to: bandLength)
                        .stroke(
                            all[i % all.count],
                            style: StrokeStyle(lineWidth: lw(scale) * 1.5, lineCap: .round)
                        )
                        .rotationEffect(.radians(bandPhase))
                        .opacity(min(0.25 + 0.45 * pulse + voiceLevel * 0.2, 1))
                        .blur(radius: lw(scale) * 0.4)
                }
            },
            color: all[0],
            boost: voiceLevel,
            scale: scale
        )
    }

    /// A liquid-level gauge feel: the ring fills clockwise from the bottom
    /// like rising fluid, its level slowly rising and falling on a slow
    /// sine, with a faster small wobble layered on top so the "surface"
    /// reads as sloshing rather than a flat progress sweep. A brighter,
    /// slightly wider cap at the leading edge stands in for the meniscus.
    private func liquidFillRing(phase: Double, elapsed: Double, voiceLevel: Double, scale: CGFloat) -> some View {
        let (p, s) = colors(elapsed: elapsed)
        let riseCycles = elapsed * config.speed * 0.35
        let levelBase = (sin(riseCycles * 2 * Double.pi) + 1) / 2
        let slosh = sin(elapsed * config.speed * 2 * Double.pi * 1.8) * 0.04
        let level = min(max(levelBase + slosh, 0.02), 0.98)
        return glow(
            ZStack {
                Circle()
                    .stroke(p.opacity(0.12), lineWidth: lw(scale))
                Circle()
                    .trim(from: 0, to: level)
                    .stroke(gradient(elapsed: elapsed), style: StrokeStyle(lineWidth: lw(scale), lineCap: .round))
                    .rotationEffect(.radians(.pi / 2))
                Circle()
                    .trim(from: max(level - 0.015, 0), to: level)
                    .stroke(s, style: StrokeStyle(lineWidth: lw(scale) * 1.3, lineCap: .round))
                    .rotationEffect(.radians(.pi / 2))
            },
            color: p,
            boost: voiceLevel,
            scale: scale
        )
    }

    /// Deterministic pseudo-random value in 0..<1 for a given index — the
    /// classic GLSL "hash from sine" trick. Not cryptographic, just needs
    /// to look scattered and stay identical every time the same index is
    /// evaluated, on every platform (used by `.equalizer` and `.sparkle`,
    /// and mirrored exactly in the code exporters).
    private func pseudoRandom(_ i: Int) -> Double {
        let x = sin(Double(i) * 12.9898) * 43758.5453
        return x - x.rounded(.down)
    }

    // Particle rendering (all 3 emission styles) has moved to a real
    // CAEmitterLayer — see RingParticleEmitter.swift / RingParticleEmitterView.swift.
}
