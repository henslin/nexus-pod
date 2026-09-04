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
    ///
    /// A recorded firmware stream outranks it. `patternStyle` short-circuits
    /// the whole diode path — it renders through `LEDCuePreviewView`
    /// instead — so a timeline step that is a window into a stream *and*
    /// names a spec-sheet style would draw the style and never reach the
    /// stream. The steps do both on purpose: the style is what the phase
    /// falls back to once you step down off the stream, and the stream is
    /// what it shows until then.
    private var effectivePatternStyle: LEDPatternStyle? {
        guard config.firmwarePatternStream == nil else { return nil }
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
        if config.diodeModeEnabled {
            // Every type goes through the same fixed ring of diodes — see
            // `diodeFieldRing`. The types that were already diode-based
            // (Alternating, Sparkle, Multi Chase) keep their exact look,
            // because their mappings in `diodeIntensity` are the same math
            // their dedicated renderers use.
            diodeFieldRing(phase: phase, elapsed: elapsed, voiceLevel: voiceLevel, scale: scale)
        } else {
            continuousContent(phase: phase, elapsed: elapsed, voiceLevel: voiceLevel, scale: scale)
        }
    }

    @ViewBuilder
    private func continuousContent(phase: Double, elapsed: Double, voiceLevel: Double, scale: CGFloat) -> some View {
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
        case .bloom:
            bloomRing(phase: phase, elapsed: elapsed, voiceLevel: voiceLevel, scale: scale)
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
    /// Rendered time snapped to the firmware tick — see
    /// `RingConfig.firmwareTickMs`. Passthrough when the tick is 0.
    private func quantized(_ elapsed: Double) -> Double {
        let tick = config.firmwareTickMs / 1000
        guard tick > 0 else { return elapsed }
        return (elapsed / tick).rounded(.down) * tick
    }

    /// `easedPhase` as a plain value, so the diode path can re-derive phase
    /// from quantized time instead of receiving the continuous one.
    private func easedPhaseValue(elapsed: Double) -> Double {
        easedPhase(elapsed: elapsed)
    }

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
        return glow(
            diodeLayer(count: count, scale: scale) { i in
                // The on/off blink groups stay strict even/odd (unrelated
                // to color count) — colors cycle through every configured
                // slot independently, so more colors just means more
                // distinct diodes, still swapping the same two blink
                // groups back and forth.
                let isEven = i.isMultiple(of: 2)
                return DiodeState(
                    color: all[i % all.count],
                    opacity: isEven ? blink : 1 - blink
                )
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
    // MARK: - Bloom

    /// One patch of color: where it sits, how wide it is, and how strongly
    /// it's glowing right now.
    private struct Bloom {
        var center: Double
        var length: Double
        var colorIndex: Int
        var intensity: Double

        var start: Double { center - length / 2 }
    }

    /// The whole bloom field at a moment in time.
    ///
    /// Each patch runs a surface-and-submerge cycle rather than pulsing in
    /// place: its exposed width grows from nothing to a peak and shrinks
    /// back to nothing, and the next time it comes up it does so somewhere
    /// else, at a different size, in a different color. Like something
    /// breaking the surface of water and sinking again.
    ///
    /// That's why the seeds take the cycle number as well as the patch
    /// index — see `pseudoRandom(_:_:)`. Seeding on the index alone is
    /// what pinned the earlier version to fixed spots.
    ///
    /// Every value is still hashed rather than drawn from a real RNG, for
    /// the same reason `.sparkle` and `.equalizer` are: the export path
    /// has to reproduce identical frames. "Random" here means
    /// unrelated-looking and stable, not unpredictable.
    ///
    /// The period is deliberately long (a `6 /` divisor against a speed
    /// already low) because this reads as breathing rather than motion —
    /// at the rate the travelling animations run it looks like flicker.
    private func blooms(elapsed: Double, colorCount: Int) -> [Bloom] {
        let count = max(Int(config.bloomCount.rounded()), 2)
        let base = max(config.trailFraction, 0.02)
        let colors = max(colorCount, 1)

        return (0..<count).map { i in
            // Each patch keeps its own period, so they never fall into
            // step with each other.
            let rateSeed = pseudoRandom(i + 211)
            let period = max(6.0 / max(config.speed, 0.05) * (0.55 + rateSeed), 0.3)

            let local = elapsed / period
            let cycle = Int(local.rounded(.down))
            // Progress through *this* surfacing, 0...1.
            let f = local - Double(cycle)

            // Rerolled per surfacing: where it comes up, how far it comes
            // up, which way it drifts while up, and what color it is.
            let placeSeed = pseudoRandom(i, cycle)
            let peakSeed = pseudoRandom(i, cycle + 4096)
            let driftSeed = pseudoRandom(i, cycle + 8192)
            let colorSeed = pseudoRandom(i, cycle + 16384)

            // 0 → 1 → 0 across the cycle: the whole shape of surfacing and
            // sinking back. Both width and brightness follow it, so a
            // patch genuinely shrinks into nothing rather than just fading
            // while staying the same size.
            let envelope = sin(f * Double.pi)

            // How exposed it gets *this* time — a third to full size, so
            // consecutive surfacings of the same patch differ.
            let peak = 0.33 + peakSeed * 0.67
            let length = base * peak * envelope

            // A slow sideways travel while it's up, so a patch isn't
            // pinned to one spot even within a single surfacing.
            let drift = (driftSeed - 0.5) * 0.15 * f
            let center = placeSeed + drift

            return Bloom(
                center: center,
                length: length,
                colorIndex: Int(colorSeed * Double(colors)) % colors,
                intensity: pow(envelope, 1.4) * (0.55 + peakSeed * 0.45)
            )
        }
    }

    /// Irregular patches that swell on top of an always-lit ring — see
    /// `blooms`.
    ///
    /// The base is the same full angular gradient `.wave` sweeps, held
    /// still at `bloomBase` strength. That's what keeps every part of the
    /// ring showing its color at all times: patches *add* brightness to a
    /// lit ring rather than being the only thing lit, so there are no dark
    /// or dull stretches between them.
    ///
    /// Patches composite with `.plusLighter` so two crossing genuinely add
    /// up instead of one covering the other, and so a patch over the base
    /// lifts it rather than replacing it. That accumulation is what makes
    /// a peak read as brighter *and* more saturated, which is the
    /// "vibrancy" half of the effect.
    private func bloomRing(phase: Double, elapsed: Double, voiceLevel: Double, scale: CGFloat) -> some View {
        let all = activeColors(elapsed: elapsed)
        let field = blooms(elapsed: elapsed, colorCount: all.count)
        let softness = max(config.bloomSoftness, 0)

        return glow(
            ZStack {
                Circle()
                    .stroke(gradient(elapsed: elapsed), style: StrokeStyle(lineWidth: lw(scale), lineCap: .round))
                    .opacity(min(max(config.bloomBase, 0), 1))

                ForEach(Array(field.enumerated()), id: \.offset) { _, bloom in
                    // A patch is fully submerged for part of its cycle.
                    // `trim` with a zero-length range draws a *full
                    // circle* in some renderers rather than nothing (the
                    // same trap `chasingArc` guards against), so hold a
                    // hair of length and let opacity do the hiding.
                    let drawn = max(bloom.length, 0.0005)
                    Circle()
                        .trim(from: bloom.start, to: bloom.start + drawn)
                        .stroke(
                            all[bloom.colorIndex % all.count],
                            style: StrokeStyle(
                                // Wider as it brightens, so a peak blooms
                                // outward rather than only getting paler.
                                lineWidth: lw(scale) * CGFloat(0.75 + bloom.intensity * 0.5),
                                lineCap: .round
                            )
                        )
                        .rotationEffect(.degrees(-90))
                        .opacity(min(bloom.intensity + voiceLevel * 0.25, 1))
                        // Zero softness has to skip the modifier entirely —
                        // `.blur(radius: 0)` still forces an offscreen pass
                        // and softens edges slightly, which is exactly what
                        // turning it to 0 is meant to avoid.
                        .modifier(OptionalBlur(radius: softness > 0 ? lw(scale) * CGFloat(softness) : nil))
                        .blendMode(.plusLighter)
                }
            },
            color: all[0],
            boost: voiceLevel,
            scale: scale
        )
    }

    /// Applies `.blur` only when there's a radius to apply — see the call
    /// site in `bloomRing`.
    private struct OptionalBlur: ViewModifier {
        var radius: CGFloat?

        func body(content: Content) -> some View {
            if let radius {
                content.blur(radius: radius)
            } else {
                content
            }
        }
    }

    // MARK: - Diodes

    /// The ring's band width at the current scale — what `lineWidth` means
    /// once diodes are involved. Diodes are centered on this band and
    /// cropped to it.
    private func bandWidth(scale: CGFloat) -> CGFloat { lw(scale) }

    /// How big each diode is drawn, before the band crops it. A
    /// `diodeScale` above 1 deliberately overflows the band.
    private func diodeSize(scale: CGFloat) -> CGFloat {
        lw(scale) * CGFloat(max(config.diodeScale, 0.1))
    }

    /// Radius the diode centers sit on.
    ///
    /// Derived from the *band* width, not the diode size — so making
    /// diodes larger makes them overflow and get cropped, rather than
    /// silently pulling the whole ring inward to fit them. At the default
    /// `diodeScale` of 1 the two are identical, which is why nothing
    /// already saved moves.
    private func diodeRadius(in size: CGSize, scale: CGFloat) -> CGFloat {
        min(size.width, size.height) / 2 - bandWidth(scale: scale) / 2
    }

    /// The annulus a diode layer is clipped to: a circle of `radius`,
    /// stroked to `width`.
    ///
    /// This is what makes an oversized diode read as hardware — an LED
    /// seen through a slot or diffuser shows as a cropped band of a larger
    /// emitter, not as the whole component floating on a circle.
    private struct RingBand: Shape {
        var radius: CGFloat
        var width: CGFloat

        func path(in rect: CGRect) -> Path {
            let box = CGRect(
                x: rect.midX - radius,
                y: rect.midY - radius,
                width: radius * 2,
                height: radius * 2
            )
            return Path(ellipseIn: box).strokedPath(StrokeStyle(lineWidth: width))
        }
    }

    /// What one diode looks like this frame.
    struct DiodeState {
        var color: Color
        var opacity: Double
        /// Extra size multiplier on top of `diodeScale`, for animations
        /// that scale individual diodes (Sparkle). Ignored by `.segment`,
        /// which always fills the band.
        var sizeScale: CGFloat = 1
    }

    /// Draws a full ring of `count` diodes, asking `state(_:)` what each
    /// one looks like.
    ///
    /// One implementation for all four diode-based animations, which
    /// previously each laid out their own ring. That duplication was
    /// survivable when a diode was always a circle; it stopped being so
    /// once `DiodeShape.segment` needed a structurally different drawing
    /// path — arcs that slice the ring, rather than shapes positioned on
    /// it — because that would have meant writing the same branch four
    /// times and keeping them agreeing forever.
    private func diodeLayer(
        count: Int,
        scale: CGFloat,
        /// A faint continuous track drawn behind the diodes. Sparkle uses
        /// one so the ring's shape stays readable when most points are
        /// dark; the others pass 0 for none.
        backingTrack: (color: Color, opacity: Double)? = nil,
        state: @escaping (Int) -> DiodeState
    ) -> some View {
        let band = bandWidth(scale: scale)
        let size = diodeSize(scale: scale)
        let isSegmented = config.diodeShape.dividesTheRing

        return GeometryReader { geo in
            let radius = diodeRadius(in: geo.size, scale: scale)
            ZStack {
                if let backingTrack {
                    Circle()
                        .stroke(backingTrack.color.opacity(backingTrack.opacity), lineWidth: band * 0.4)
                        .frame(width: radius * 2, height: radius * 2)
                }
                ForEach(0..<count, id: \.self) { i in
                    let lit = state(i)
                    if isSegmented {
                        segmentDiode(index: i, count: count, radius: radius, band: band, state: lit)
                    } else {
                        let angle = (Double(i) / Double(count)) * 2 * Double.pi - .pi / 2
                        diode(color: lit.color, size: size * lit.sizeScale, angle: angle)
                            .opacity(lit.opacity)
                            .position(
                                x: geo.size.width / 2 + cos(angle) * radius,
                                y: geo.size.height / 2 + sin(angle) * radius
                            )
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            // Segments are already exactly the band — clipping them would
            // only risk shaving their edges through antialiasing.
            .clipShape(isSegmented ? AnyShape(Rectangle()) : AnyShape(RingBand(radius: radius, width: band)))
        }
    }

    /// One wedge of the donut: an arc of `1 / count` of the circle, minus
    /// `diodeGap`, stroked to the band's full thickness.
    ///
    /// `.butt` caps rather than `.round` — the whole point is a clean
    /// radial edge on each side, which is what makes neighbors read as
    /// distinct wedges instead of overlapping lozenges. The -90 rotation
    /// puts index 0 at the top, matching where the positioned shapes above
    /// place it (SwiftUI's `trim` starts at 3 o'clock).
    private func segmentDiode(index: Int, count: Int, radius: CGFloat, band: CGFloat, state: DiodeState) -> some View {
        let slice = 1.0 / Double(count)
        let gap = min(max(config.diodeGap, 0), 0.9)
        let filled = slice * (1 - gap)
        let start = Double(index) * slice + (slice - filled) / 2

        return Circle()
            .trim(from: start, to: start + filled)
            .stroke(state.color, style: StrokeStyle(lineWidth: band, lineCap: .butt))
            .frame(width: radius * 2, height: radius * 2)
            .rotationEffect(.degrees(-90))
            .opacity(state.opacity)
    }

    /// One diode, in whatever shape is configured.
    ///
    /// Square and bar shapes are rotated to sit tangent to the ring (the
    /// `+ .pi / 2` turns the radial angle into a tangential one), so they
    /// read as components mounted on a circular board rather than as a
    /// scatter of rotated dots. Round needs no rotation, being symmetric.
    @ViewBuilder
    private func diode(color: Color, size: CGFloat, angle: Double) -> some View {
        switch config.diodeShape {
        case .round:
            Circle()
                .fill(color)
                .frame(width: size, height: size)
        case .square:
            Rectangle()
                .fill(color)
                .frame(width: size, height: size)
                .rotationEffect(.radians(angle + .pi / 2))
        case .bar:
            RoundedRectangle(cornerRadius: size * 0.28)
                .fill(color)
                .frame(width: size * DiodeShape.bar.aspect, height: size)
                .rotationEffect(.radians(angle + .pi / 2))
        case .segment:
            // Never reached — `diodeLayer` routes `.segment` to
            // `segmentDiode` before getting here, since a wedge isn't a
            // shape positioned at a point. Drawn as a plain dot rather
            // than left empty so a future caller that bypasses
            // `diodeLayer` degrades visibly instead of silently vanishing.
            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
    }

    /// Renders any animation as a fixed ring of diodes that never move —
    /// only their color and brightness change.
    ///
    /// This is what addressable LED hardware actually does: the pixels are
    /// soldered in place, and an "animation" is a brightness pattern
    /// swept across them. Every continuous renderer in this file draws the
    /// opposite way — arcs that rotate, gradients that sweep, rings that
    /// scale — so this can't reuse them. Instead `diodeIntensity` restates
    /// each animation as a scalar field over ring position, which is the
    /// form hardware needs anyway.
    private func diodeFieldRing(phase: Double, elapsed: Double, voiceLevel: Double, scale: CGFloat) -> some View {
        let all = activeColors(elapsed: elapsed)
        let count = max(Int(config.diodeCount.rounded()), 2)
        // Quantize once, here, so every diode in a frame agrees on the
        // time — and so `phase` (already derived from the unquantized
        // clock) is re-derived from the same tick rather than drifting
        // against it.
        let tickedElapsed = quantized(elapsed)
        let tickedPhase = config.firmwareTickMs > 0
            ? easedPhaseValue(elapsed: tickedElapsed)
            : phase
        // Only Ripple reads this, and computing it is a sweep — so skip it
        // entirely for every other type rather than paying for it always.
        let rippleNorm = config.animationType == .ripple ? rippleNormalization() : 1
        // Resolved once per frame, never per diode: replaying the stream is
        // a walk over its events, and doing that sixteen times a frame
        // would be sixteen times the work for the same answer. Same
        // reasoning as `rippleNorm` above.
        let streamFrame = config.firmwarePatternStream
            .flatMap { FirmwarePatternStream.stream(named: $0) }
            .map { $0.frame(atSeconds: tickedElapsed + config.firmwarePatternStreamOffset, ledCount: count) }

        // Resolved up front into an array rather than left in the closure.
        // Smoothing needs the whole ring at once — a diode's level depends
        // on its neighbours — so it can't be answered one index at a time,
        // and having both paths hand `diodeLayer` the same finished array
        // keeps the hardware render the single source of what smoothing is
        // smoothing.
        let states: [DiodeState] = config.smoothingEnabled
            ? smoothedStates(
                count: count,
                elapsed: elapsed,
                voiceLevel: voiceLevel,
                colors: all,
                rippleNorm: rippleNorm
            )
            : (0..<count).map { i in
                let position = Double(i) / Double(count)
                let lit = diodeIntensity(
                    index: i,
                    position: position,
                    count: count,
                    phase: tickedPhase,
                    elapsed: tickedElapsed,
                    voiceLevel: voiceLevel,
                    colors: all,
                    rippleNorm: rippleNorm,
                    streamFrame: streamFrame
                )
                // Floor lifts and compresses rather than clipping, so the
                // low end keeps its shape — see `RingConfig.diodeFloor`.
                let floor = min(max(config.diodeFloor, 0), 1)
                let level = floor + (1 - floor) * lit.brightness
                return DiodeState(
                    color: config.diodeColorMode == .byLevel
                        ? levelColor(level, colors: all)
                        : lit.color,
                    opacity: level * blinkMultiplier(index: i, elapsed: tickedElapsed)
                )
            }

        // Same states either way — the only question is whether they're
        // drawn as twenty shapes or as one stroke sampled from all twenty.
        let ring: AnyView = config.smoothingEnabled && config.smoothingGradientRing
            ? AnyView(gradientRing(states: states, scale: scale))
            : AnyView(diodeLayer(count: count, scale: scale) { i in
                states.indices.contains(i) ? states[i] : DiodeState(color: all[0], opacity: 0)
            })

        return glow(ring, color: all[0], boost: voiceLevel, scale: scale)
    }

    /// The ring as one continuous stroke, colored by an `AngularGradient`
    /// with a stop per diode.
    ///
    /// See `RingConfig.smoothingGradientRing` for why this exists. The field
    /// is unchanged — this is purely how it's drawn — so every control above
    /// still means what it meant, and turning it off returns the twenty
    /// discrete diodes.
    private func gradientRing(states: [DiodeState], scale: CGFloat) -> some View {
        let band = bandWidth(scale: scale)
        return GeometryReader { geo in
            let radius = diodeRadius(in: geo.size, scale: scale)
            Circle()
                .stroke(ringGradient(states), style: StrokeStyle(lineWidth: band))
                .frame(width: radius * 2, height: radius * 2)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }

    /// Builds the gradient the ring is stroked with.
    ///
    /// `startAngle` is -90° because diode 0 sits at twelve o'clock (see
    /// `diodeLayer`, which places it at `-.pi / 2`) while an
    /// `AngularGradient` would otherwise start at three. Getting this wrong
    /// rotates every pattern a quarter turn, which looks like a timing bug
    /// rather than a geometry one.
    private func ringGradient(_ states: [DiodeState]) -> AngularGradient {
        let count = states.count
        guard count > 1 else {
            let only = states.first.map { $0.color.opacity($0.opacity) } ?? .clear
            return AngularGradient(colors: [only, only], center: .center)
        }

        // Converted once per diode rather than once per emitted stop —
        // `rgbComponents` goes through NSColor/UIColor, and the loop below
        // emits several stops per diode.
        let samples = states.map { state -> (r: Double, g: Double, b: Double, a: Double) in
            let rgb = state.color.rgbComponents
            return (rgb.red, rgb.green, rgb.blue, min(max(state.opacity, 0), 1))
        }

        // Extra stops *between* diodes, eased rather than linear.
        //
        // A stop per diode leaves the gradient piecewise-linear: it's
        // continuous, but its slope isn't, so every diode position is a
        // visible crease and the ring reads as twenty facets rather than one
        // sweep. Smoothstep between neighbours makes the slope continuous
        // too, at the cost of a few more stops of an already-cheap gradient.
        let subdivisions = 4
        var stops: [Gradient.Stop] = []
        stops.reserveCapacity(count * subdivisions + 1)

        for index in 0..<count {
            let from = samples[index]
            let to = samples[(index + 1) % count]
            for step in 0..<subdivisions {
                let f = Double(step) / Double(subdivisions)
                let eased = f * f * (3 - 2 * f)
                stops.append(Gradient.Stop(
                    color: Color(
                        red: from.r + (to.r - from.r) * eased,
                        green: from.g + (to.g - from.g) * eased,
                        blue: from.b + (to.b - from.b) * eased
                    ).opacity(from.a + (to.a - from.a) * eased),
                    location: (Double(index) + f) / Double(count)
                ))
            }
        }

        // Closes the loop back onto diode 0. Without a stop at exactly 1 the
        // gradient runs from the last emitted stop straight back to the first
        // across a zero-width span, which draws as a hard seam at twelve
        // o'clock — most visible on exactly the patterns this mode is for.
        let first = samples[0]
        stops.append(Gradient.Stop(
            color: Color(red: first.r, green: first.g, blue: first.b).opacity(first.a),
            location: 1
        ))

        return AngularGradient(
            stops: stops,
            center: .center,
            startAngle: .degrees(-90),
            endAngle: .degrees(270)
        )
    }

    // MARK: - Smoothing

    /// One diode's color and level at one instant, in a form that can be
    /// combined with another — `Color` can't be added together, and going
    /// through `rgbComponents` per combination rather than once per sample
    /// would be the expensive way round.
    private struct FieldSample {
        var red: Double = 0
        var green: Double = 0
        var blue: Double = 0
        var level: Double = 0
    }

    /// Combines contributions to one diode, keeping the strongest.
    ///
    /// A max, not a sum and not an average. An average dims a lone lit diode
    /// to a fraction of itself — blur a single pixel and you get a smudge,
    /// not a glow. A sum (or a p-norm, which was tried) has the opposite
    /// problem: contributions accumulate, so a pattern with colour on every
    /// diode brightens and dims as taps enter and leave the window, which
    /// measured *worse* than the max on every pattern that isn't sparse.
    ///
    /// Keeping the strongest also carries its colour, so a trail is the hue
    /// of whatever lit it rather than of the diode it passes over.
    private struct FieldAccumulator {
        private var sample = FieldSample()

        mutating func add(_ candidate: FieldSample, scaledBy scale: Double) {
            let value = candidate.level * scale
            guard value > sample.level else { return }
            sample = FieldSample(
                red: candidate.red,
                green: candidate.green,
                blue: candidate.blue,
                level: value
            )
        }

        var resolved: FieldSample {
            var out = sample
            out.level = min(max(out.level, 0), 1)
            return out
        }
    }

    /// The whole ring at one instant, before any smoothing.
    ///
    /// Deliberately re-derives `phase` and re-resolves the stream frame from
    /// the time it's given: smoothing samples the field at instants either
    /// side of now, and a phase carried in from the caller would describe
    /// the wrong one.
    private func rawField(
        at time: Double,
        count: Int,
        colors all: [Color],
        rippleNorm: Double,
        voiceLevel: Double
    ) -> [FieldSample] {
        let phase = easedPhaseValue(elapsed: time)
        // Once per sampled instant, not once per diode — same reasoning as
        // the frame resolve in `diodeFieldRing`.
        let streamFrame = config.firmwarePatternStream
            .flatMap { FirmwarePatternStream.stream(named: $0) }
            .map { $0.frame(atSeconds: time + config.firmwarePatternStreamOffset, ledCount: count) }

        return (0..<count).map { i in
            let lit = diodeIntensity(
                index: i,
                position: Double(i) / Double(count),
                count: count,
                phase: phase,
                elapsed: time,
                voiceLevel: voiceLevel,
                colors: all,
                rippleNorm: rippleNorm,
                streamFrame: streamFrame
            )
            // Blink belongs in the sample so it gets smeared along with
            // everything else — a strobe under persistence should read as a
            // pulse with a falloff, not as a strobe with a halo. The floor
            // does not: it's a display minimum, applied once at the end, and
            // folding it in here would let the trail decay *from* the floor
            // instead of to it.
            let level = lit.brightness * blinkMultiplier(index: i, elapsed: time)
            let rgb = (config.diodeColorMode == .byLevel
                       ? levelColor(level, colors: all)
                       : lit.color).rgbComponents
            return FieldSample(red: rgb.red, green: rgb.green, blue: rgb.blue, level: level)
        }
    }

    /// The smoothed ring: the raw field spread across neighbours and trailed
    /// through time.
    ///
    /// See `RingConfig.smoothingEnabled` for why both passes take a decaying
    /// max rather than a weighted average, and why the time pass resamples
    /// instead of accumulating.
    private func smoothedStates(
        count: Int,
        elapsed: Double,
        voiceLevel: Double,
        colors all: [Color],
        rippleNorm: Double
    ) -> [DiodeState] {
        // Continuous time is most of what "smooth" means for an imported
        // pattern: `quantized` is what makes a 312 ms tick visible as a
        // series of held frames.
        let base = config.smoothingFluidTime ? elapsed : quantized(elapsed)
        let release = max(config.smoothingTrail, 0)
        // A short look *forward*, which softens the rise. Possible only
        // because the field is a pure function of time — there's no "next
        // frame" to wait for, just another instant to evaluate.
        //
        // Capped in absolute terms rather than kept proportional, and the cap
        // is the whole point.
        //
        // A look-ahead is what stops a diode popping on at full brightness:
        // without one, the worst single-frame jump on a comet goes from 38%
        // to 51%. But it's also the main source of the flicker at long
        // persistence — a diode gets lit by the *coming* frame's halo and the
        // *previous* frame's halo in turn, and the handover between them
        // reverses direction. Kept proportional at 0.35 it reached 0.28 s at
        // the top of the Persistence range, which put 18 direction reversals
        // into two seconds of comet.
        //
        // 120 ms was measured, not picked: it leaves the default setting
        // exactly as it was (2 reversals, 38% worst step) while taking the
        // extreme from 18 reversals to 2. Both 80 and 100 ms were worse at
        // the default without being better at the extreme.
        let attack = min(release * 0.35, 0.12)

        var accumulators = [FieldAccumulator](repeating: FieldAccumulator(), count: count)
        let now = rawField(
            at: base, count: count, colors: all, rippleNorm: rippleNorm, voiceLevel: voiceLevel
        )
        for index in 0..<count {
            accumulators[index].add(now[index], scaledBy: 1)
        }

        for tap in temporalTaps(base: base, release: release, attack: attack) {
            // Clamped rather than skipped: at t = 0 a backward tap would
            // otherwise wrap into negative time, where a stream replay has no
            // events and every pattern reads as dark — so the first fraction
            // of a second would smooth *toward* black.
            let sampled = rawField(
                at: max(tap.time, 0), count: count,
                colors: all, rippleNorm: rippleNorm, voiceLevel: voiceLevel
            )
            for index in 0..<count where index < sampled.count {
                accumulators[index].add(sampled[index], scaledBy: tap.weight)
            }
        }

        var field = accumulators.map(\.resolved)

        let spread = max(config.smoothingSpread, 0)
        if spread > 0.01 {
            field = spatiallySpread(field, spread: spread)
        }

        let floor = min(max(config.diodeFloor, 0), 1)
        return field.map { sample in
            let level = floor + (1 - floor) * min(max(sample.level, 0), 1)
            return DiodeState(
                color: Color(red: sample.red, green: sample.green, blue: sample.blue),
                opacity: level
            )
        }
    }

    private func uniformTaps(base: Double, release: Double, attack: Double) -> [(time: Double, weight: Double)] {
        let pastTaps = 6
        let futureTaps = 3
        var taps: [(time: Double, weight: Double)] = []
        // Weights land on e^-3 ≈ 0.05 at the far end of each side, so the
        // trail fades out within the time asked for instead of being cut off
        // mid-decay.
        for k in 1...pastTaps {
            let f = Double(k) / Double(pastTaps)
            taps.append((base - f * release, exp(-3 * f)))
        }
        if attack > 0.001 {
            for k in 1...futureTaps {
                let f = Double(k) / Double(futureTaps)
                taps.append((base + f * attack, exp(-3 * f)))
            }
        }
        return taps
    }

    /// When to sample the field, and how much each sample counts.
    ///
    /// **Frame-aligned when the source is quantized**, which is the whole
    /// point of this function existing rather than a loop at the call site.
    ///
    /// Sampling at `base - kΔ` — evenly spaced behind the playhead — flickers
    /// on any pattern with a firmware tick. Each tap crosses a frame boundary
    /// at a different moment, and because the fold below keeps a decaying
    /// *max*, a tap crossing swaps in an entirely different frame's LEDs and
    /// the visible level jumps by that tap's whole weight. At a 312 ms tick
    /// and a 0.3 s trail the nearest tap carries ~0.6 of full brightness, so
    /// that's a 60% jump, six times per tick.
    ///
    /// Sampling the *frames themselves* — at multiples of the tick — fixes it
    /// outright: the sampled values are then constant between frame changes
    /// and only the weights move, continuously, as the playhead advances. A
    /// frame keeps its own absolute timestamp for as long as it's in the
    /// window, so its age (and its weight) never jumps.
    ///
    /// The forward taps are what make the *arrival* of a new frame continuous
    /// too. Without them the newest frame appears at full weight the instant
    /// the playhead crosses into it; with them it has already been fading up
    /// across the preceding `attack`, and at the crossing its weight is
    /// exactly 1 either side.
    ///
    /// An unquantized source needs none of this — its value varies
    /// continuously with the sample time, so evenly spaced taps are already
    /// smooth — and gets the simple version.
    private func temporalTaps(
        base: Double,
        release: Double,
        attack: Double
    ) -> [(time: Double, weight: Double)] {
        guard release > 0.001 else { return [] }

        // A recorded stream carries its own boundaries, and they're the ones
        // that matter: `firmwareTickMs` is 0 for most of these patterns —
        // including the comet and the rainbow, the two this is most visible
        // on — because their timing lives in the event timestamps rather than
        // in a nominal rate.
        if let stream = config.firmwarePatternStream
            .flatMap({ FirmwarePatternStream.stream(named: $0) }) {
            let offset = config.firmwarePatternStreamOffset
            let now = base + offset
            let boundaries = stream.frameBoundaries(
                around: now, back: release, forward: attack, limit: 24
            )
            if !boundaries.isEmpty {
                return boundaries.enumerated().map { index, boundary in
                    // Half a millisecond *inside* the frame this boundary
                    // opens. Replay takes every event with `timeMs <= t`, and
                    // sampling exactly on the boundary is one rounding error
                    // away from returning the previous frame instead. Event
                    // times are whole milliseconds, so this is safely inside.
                    let time = boundary + 0.0005 - offset
                    if boundary <= now {
                        // Age measured from when this frame stopped being the
                        // current one — so the frame the playhead is inside
                        // counts for a full 1 however far through it we are,
                        // and a ring that never changes never dims.
                        let endsAt = index + 1 < boundaries.count ? boundaries[index + 1] : now
                        return (time, exp(-3 * max(now - endsAt, 0) / release))
                    }
                    guard attack > 0.001 else { return (time, 0) }
                    return (time, exp(-3 * (boundary - now) / attack))
                }
            }
        }

        let tick = config.firmwareTickMs / 1000

        guard tick >= 0.001 else {
            return uniformTaps(base: base, release: release, attack: attack)
        }

        // Capped rather than unbounded: a long trail over a short tick is a
        // lot of frames, and each one is a full sweep of the ring plus a
        // stream resolve. Twenty-four covers a 0.8 s trail at the 50 ms tick
        // these patterns quantize to at their finest.
        let maxTaps = 24
        let latest = (base / tick).rounded(.down) * tick
        var taps: [(time: Double, weight: Double)] = []

        let back = min(Int((release / tick).rounded(.up)) + 1, maxTaps)
        for n in 0...back {
            let time = latest - Double(n) * tick
            // Age *past the current frame*, not raw age. The frame the
            // playhead is inside spans ages 0..<tick and has to count for a
            // full 1 the whole way through it, or a ring that never changes
            // dims as the playhead crosses the frame and snaps back at the
            // boundary — the flicker, reintroduced from the other side.
            // Starting the decay at `tick` also makes the weight continuous
            // when a frame shifts from being the current one to being one
            // behind: both sides read 1 at exactly that instant.
            let age = max(base - time - tick, 0)
            taps.append((time, exp(-3 * age / release)))
        }

        if attack > 0.001 {
            let forward = min(Int((attack / tick).rounded(.up)), maxTaps)
            if forward > 0 {
                for n in 1...forward {
                    let time = latest + Double(n) * tick
                    let ahead = time - base
                    taps.append((time, exp(-3 * ahead / attack)))
                }
            }
        }
        return taps
    }

    /// Bleeds each diode into its neighbours with a Gaussian falloff,
    /// wrapping around the ring.
    ///
    /// A dilation, not a blur: each diode takes the brightest thing near it,
    /// attenuated by distance. So a solid arc stays solid, a lone lit diode
    /// keeps its full brightness and grows a halo, and the hard edges the
    /// firmware's level threshold produces become gradients.
    private func spatiallySpread(_ field: [FieldSample], spread: Double) -> [FieldSample] {
        let n = field.count
        guard n > 1 else { return field }
        // Past two sigma the weight is under 0.14 and, on a twenty-diode
        // ring, a wider reach starts wrapping onto itself.
        let radius = min(max(Int(ceil(spread * 2)), 1), n / 2)

        return (0..<n).map { index in
            var accumulator = FieldAccumulator()
            for offset in -radius...radius {
                let weight = exp(-Double(offset * offset) / (2 * spread * spread))
                let neighbour = ((index + offset) % n + n) % n
                accumulator.add(field[neighbour], scaledBy: weight)
            }
            return accumulator.resolved
        }
    }

    /// One drop: when it landed, and where on the ring.
    private struct Drop {
        var landedAt: Double
        var center: Double
    }

    /// Seeded drop placement across one loop.
    ///
    /// Hashed rather than drawn from an RNG, for the same reason every
    /// other "random" here is: the exporter has to reproduce identical
    /// frames. Paging through `rippleSeed` reshuffles the arrangement,
    /// which is how these are authored.
    private func drops() -> [Drop] {
        let count = max(Int(config.rippleDropCount.rounded()), 1)
        let loop = max(config.loopSeconds, 0.1)
        let seed = Int(config.rippleSeed.rounded())
        return (0..<count).map { i in
            Drop(
                landedAt: pseudoRandom(seed, i) * loop,
                center: pseudoRandom(seed, i + 5000)
            )
        }
    }

    /// Accumulated ripple brightness at a point on the ring.
    ///
    /// Each live drop contributes a Gaussian front expanding outward from
    /// its center in *both* directions, decaying as it goes. Contributions
    /// **sum** rather than taking the brightest: two fronts crossing should
    /// reinforce, which is what makes overlapping ripples read as water
    /// rather than as two shapes passing through each other.
    ///
    /// Every drop is also evaluated one loop earlier and one later. Without
    /// that, a drop landing near the end of the loop would be cut off
    /// mid-expansion when the pattern repeats, and the seam would be
    /// visible as a stutter — this is the whole reason `loopSeconds`
    /// exists as a parameter rather than being implicit.
    private func rippleLevel(at position: Double, elapsed: Double) -> Double {
        let loop = max(config.loopSeconds, 0.1)
        let life = max(config.rippleLife, 0.05)
        let width = max(config.trailFraction, 0.01)
        let t = elapsed.truncatingRemainder(dividingBy: loop)
        var total = 0.0

        for drop in drops() {
            for offset in [0.0, -loop, loop] {
                let age = t - (drop.landedAt + offset)
                guard age >= 0, age <= life else { continue }
                // Front position, as a fraction of the ring travelled from
                // the drop. `speed` is laps/second and a symmetric front
                // covers half the ring, so it reaches the far side in
                // 0.5 / speed seconds.
                let front = age * config.speed
                var apart = abs(position - drop.center).truncatingRemainder(dividingBy: 1)
                if apart > 0.5 { apart = 1 - apart }
                let offsetFromFront = (apart - front) / width
                let pulse = exp(-0.5 * offsetFromFront * offsetFromFront)
                total += pulse * exp(-config.rippleDecay * age)
            }
        }
        return total
    }

    /// Peak of `rippleLevel` over one loop, used to normalize.
    ///
    /// Without it, brightness scales with however many drops happen to
    /// overlap — three drops crossing would blow past full while a lone one
    /// never reaches it.
    ///
    /// Sampled rather than solved, and deliberately **once per frame**, not
    /// once per diode: the first version called this from inside
    /// `diodeIntensity`, which made it a 1,152-sample sweep per diode per
    /// frame — sixty times a second across up to sixty diodes. Hoisting it
    /// into `diodeFieldRing` and passing the result down makes it one sweep
    /// a frame, and only when Ripple is the active type.
    private func rippleNormalization() -> Double {
        let loop = max(config.loopSeconds, 0.1)
        var peak = 0.0001
        for step in 0..<32 {
            let t = loop * Double(step) / 32
            for p in 0..<16 {
                peak = max(peak, rippleLevel(at: Double(p) / 16, elapsed: t))
            }
        }
        return peak
    }

    /// Each animation type restated as "how bright is the diode at this
    /// position, and what color".
    ///
    /// Some translate exactly: Alternating, Sparkle, Multi Chase and
    /// Equalizer are already per-position, so these are the same
    /// expressions their own renderers use. Others are interpretations,
    /// and deliberately so — Ripple and Wobble are *radial* effects
    /// (circles scaling outward, a radius undulating) and a fixed ring of
    /// pixels has no radius to vary, so they become a travelling front and
    /// a standing wave respectively. That's the closest honest reading of
    /// each on hardware, not a bug to be fixed later.
    private func diodeIntensity(
        index: Int,
        position: Double,
        count: Int,
        phase: Double,
        elapsed: Double,
        voiceLevel: Double,
        colors all: [Color],
        rippleNorm: Double,
        streamFrame: FirmwarePatternStream.Frame? = nil
    ) -> (color: Color, brightness: Double) {
        // A recorded command stream outranks everything: it isn't a model
        // of the device's output, it is the device's output. A dark LED is
        // genuinely dark here — these patterns turn pixels off as well as
        // recoloring them — so brightness goes to 0 rather than to a floor.
        if let streamFrame, index < streamFrame.leds.count {
            if let color = streamFrame.leds[index] {
                return (color, 1)
            }
            return (streamFrame.color0, 0)
        }

        // The firmware's own field, when the pattern came from one.
        //
        // Short-circuits `animationType` entirely: this *is* what the device
        // computes, so there is nothing to approximate. The engine writes
        // one of two palette registers and never deselects an LED, so both
        // states are full brightness and the level picks the color rather
        // than dimming it — no ramp between them, because the hardware has
        // none. See `FirmwareLevelField`.
        if let field = config.firmwareLevelField {
            let lit = field.isLit(index: index, time: elapsed)
            let color0 = all[0]
            let color1 = all.count > 1 ? all[1] : all[0]
            return (lit ? color1 : color0, 1)
        }

        let head = phase / (2 * Double.pi)
        let ownColor = all[index % all.count]
        let floorBrightness = 0.06

        switch config.animationType {
        case .wave:
            // A single crest travelling around fixed, individually-colored
            // pixels — the hardware reading of a sweeping gradient.
            let offset = (position - head).truncatingRemainder(dividingBy: 1)
            let crest = (cos(offset * 2 * Double.pi) + 1) / 2
            return (ownColor, max(crest, floorBrightness))

        case .chasing:
            let lit = brightestComet(at: position, head: head, tail: max(config.trailFraction, 0.02), colorCount: 1)
            return (all[0], max(lit.brightness, floorBrightness))

        case .dualChase:
            let tail = max(config.trailFraction, 0.02)
            let forward = brightestComet(at: position, head: head, tail: tail, colorCount: 1)
            let backward = brightestComet(at: position, head: -head, tail: tail, colorCount: 1)
            let secondary = all.count > 1 ? all[1] : all[0]
            return forward.brightness >= backward.brightness
                ? (all[0], max(forward.brightness, floorBrightness))
                : (secondary, max(backward.brightness, floorBrightness))

        case .multiChase:
            let lit = brightestComet(at: position, head: head, tail: max(config.trailFraction, 0.02), colorCount: all.count)
            return (all[lit.colorIndex % all.count], lit.brightness)

        case .alternating:
            let blink = (sin(phase) + 1) / 2
            return (ownColor, index.isMultiple(of: 2) ? blink : 1 - blink)

        case .pulse:
            let breath = (sin(phase) + 1) / 2
            return (ownColor, min(0.25 + 0.75 * breath + voiceLevel * 0.3, 1))

        case .ripple:
            // Drops landing at seeded positions and expanding symmetrically,
            // overlapping and accumulating — see `rippleLevel`. With
            // `rippleDropCount` at 1 this is still a single front, just one
            // that can land somewhere other than the top.
            let level = min(rippleLevel(at: position, elapsed: elapsed) / rippleNorm, 1)
            return (ownColor, max(level, floorBrightness))

        case .wobble:
            // The undulating radius becomes an undulating brightness — a
            // standing wave of three lobes, drifting with the phase.
            let lobes = 3.0
            let value = (sin(position * lobes * 2 * Double.pi + phase) + 1) / 2
            return (ownColor, 0.35 + 0.65 * value)

        case .equalizer:
            // Same seeded independent pulse `equalizerRing` gives each
            // segment, one per diode here.
            let seed = pseudoRandom(index)
            let localPhase = elapsed * config.speed * 2 * Double.pi * (0.6 + seed * 0.8) + seed * 2 * Double.pi
            let value = min((sin(localPhase) + 1) / 2 + voiceLevel * 0.4, 1)
            return (ownColor, 0.15 + value * 0.85)

        case .sparkle:
            // Same expression as `sparkleRing`.
            let seed = pseudoRandom(index)
            let cycles = elapsed * config.speed * (0.5 + seed) + seed * 4
            let f = cycles - cycles.rounded(.down)
            let brightness = max(0, 1 - f * 4)
            return (ownColor, min(0.15 + brightness * 0.85 + voiceLevel * 0.2, 1))

        case .aurora:
            // Three soft bands drifting at their own rates; a diode takes
            // whichever band covers it most strongly.
            var best = (color: all[0], brightness: floorBrightness)
            for band in 0..<3 {
                let seed = pseudoRandom(band)
                let bandSpeed = config.speed * (0.12 + seed * 0.22)
                let bandPhase = (elapsed * bandSpeed + seed).truncatingRemainder(dividingBy: 1)
                let bandLength = 0.22 + seed * 0.16
                var within = (position - bandPhase).truncatingRemainder(dividingBy: 1)
                if within < 0 { within += 1 }
                guard within < bandLength else { continue }
                // Soft falloff toward each edge rather than a hard cut, to
                // match the blurred stroke the continuous version draws.
                let edge = sin((within / bandLength) * Double.pi)
                let pulse = 0.5 + 0.5 * sin(elapsed * (0.3 + seed * 0.4) + seed * 6)
                let brightness = min(edge * (0.35 + 0.5 * pulse) + voiceLevel * 0.2, 1)
                if brightness > best.brightness {
                    best = (all[band % all.count], brightness)
                }
            }
            return best

        case .bloom:
            // The lit floor, matching what `bloomRing` draws underneath:
            // this diode's share of the gradient, at `bloomBase`. Never
            // the generic dim fallback, so no diode sits dark.
            let band = Int(position * Double(all.count)) % all.count
            let base = min(max(config.bloomBase, 0), 1)
            var best = (color: all[band], brightness: base)

            // Strongest patch covering this diode wins, with a cosine
            // falloff from its center so a patch's edges fade rather than
            // cutting off — the diode reading of the blurred arc. Its
            // brightness is added to the floor rather than replacing it,
            // matching `.plusLighter` in the continuous path.
            for bloom in blooms(elapsed: elapsed, colorCount: all.count) {
                var offset = (position - bloom.center).truncatingRemainder(dividingBy: 1)
                if offset < -0.5 { offset += 1 }
                if offset > 0.5 { offset -= 1 }
                let half = bloom.length / 2
                guard abs(offset) < half, half > 0 else { continue }
                let falloff = (cos(offset / half * Double.pi) + 1) / 2
                let brightness = min(base + falloff * bloom.intensity + voiceLevel * 0.2, 1)
                if brightness > best.brightness {
                    best = (all[bloom.colorIndex % all.count], brightness)
                }
            }
            return best

        case .liquidFill:
            // Diodes below the surface are lit, the one at the surface
            // brighter — a level gauge, which is what this already is.
            let riseCycles = elapsed * config.speed * 0.35
            let levelBase = (sin(riseCycles * 2 * Double.pi) + 1) / 2
            let slosh = sin(elapsed * config.speed * 2 * Double.pi * 1.8) * 0.04
            let level = min(max(levelBase + slosh, 0.02), 0.98)
            guard position <= level else { return (all[0], floorBrightness) }
            let isSurface = position > level - (1.0 / Double(count))
            let surfaceColor = all.count > 1 ? all[1] : all[0]
            return isSurface ? (surfaceColor, 1) : (all[0], 0.85)
        }
    }

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
        // Fraction of the ring each comet's tail covers. Guarded above
        // zero so a comet is never zero-length (which would light nothing
        // at all and look like the animation had stopped).
        let tail = max(config.trailFraction, 0.02)
        let head = phase / (2 * Double.pi)

        return glow(
            diodeLayer(count: count, scale: scale) { i in
                let position = Double(i) / Double(count)
                let lit = brightestComet(at: position, head: head, tail: tail, colorCount: all.count)
                return DiodeState(
                    color: all[lit.colorIndex % all.count],
                    opacity: lit.brightness * blinkMultiplier(index: i, elapsed: elapsed)
                )
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

    /// The palette read as a brightness ramp rather than a per-diode
    /// lookup — see `DiodeColorMode.byLevel`.
    ///
    /// Interpolates across every configured color in order: the first at
    /// black, the last at full. With three colors that's exactly the shape
    /// an LED ring script writes by hand — a low tint, a mid, and a hot
    /// core — except the core here is whatever you set rather than being
    /// hardcoded to white.
    ///
    /// Interpolation is in plain sRGB components. Not perceptually
    /// uniform, but it's what the hardware crossfade does too, so matching
    /// it is the point rather than a shortcut.
    private func levelColor(_ level: Double, colors: [Color]) -> Color {
        guard colors.count > 1 else { return colors.first ?? .white }
        let clamped = min(max(level, 0), 1)
        let scaled = clamped * Double(colors.count - 1)
        let index = min(Int(scaled), colors.count - 2)
        let t = scaled - Double(index)

        let low = colors[index].rgbComponents
        let high = colors[index + 1].rgbComponents
        return Color(
            red: low.red + (high.red - low.red) * t,
            green: low.green + (high.green - low.green) * t,
            blue: low.blue + (high.blue - low.blue) * t
        )
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
        return glow(
            diodeLayer(count: count, scale: scale, backingTrack: (all[0], 0.1)) { i in
                let seed = pseudoRandom(i)
                let cycles = elapsed * config.speed * (0.5 + seed) + seed * 4
                let f = cycles - cycles.rounded(.down)
                // Bright for the first quarter of this point's own cycle, dim the rest.
                let brightness = max(0, 1 - f * 4)
                return DiodeState(
                    color: all[i % all.count],
                    opacity: 0.15 + brightness * 0.85 + voiceLevel * 0.2,
                    // Size varies per diode here, which is why `DiodeState`
                    // carries a scale at all.
                    sizeScale: CGFloat(0.6 + brightness * 0.6)
                )
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

    /// Two-input version of the same hash, for values that must differ per
    /// *occurrence* rather than per index.
    ///
    /// `.bloom` needs this: a patch's position and size are rerolled every
    /// time it surfaces, so the seed has to depend on which surfacing this
    /// is, not just which patch. Seeding on the index alone is what made
    /// the first version sit in fixed spots forever.
    private func pseudoRandom(_ a: Int, _ b: Int) -> Double {
        let x = sin(Double(a) * 12.9898 + Double(b) * 78.233) * 43758.5453
        return x - x.rounded(.down)
    }

    // Particle rendering (all 3 emission styles) has moved to a real
    // CAEmitterLayer — see RingParticleEmitter.swift / RingParticleEmitterView.swift.
}
