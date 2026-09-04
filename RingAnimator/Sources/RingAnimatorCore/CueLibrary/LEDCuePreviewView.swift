import SwiftUI

/// Renders a live preview of a single LED cue from its `LEDCueParameters`.
/// Every `LEDPatternStyle` case has a distinct rendering here so the team
/// can see, at a glance, what a cue currently communicates — separate from
/// `RingView`, which renders the 11 continuous "AI thinking" animations
/// used elsewhere in the app... with one exception: `.continuousAnimation`
/// (see that case's doc comment) is rendered by handing an equivalent
/// `RingConfig` straight to a real `RingView` (`animationConfig` below)
/// instead of reimplementing any of those 11 animations a second time here.
/// That's what actually guarantees Cue Library ↔ Nexus parity for
/// that style, rather than two hand-maintained copies that can drift apart.
///
/// The same motion effects available in Nexus (easing, scale
/// pulse, hue shift, blur, blend mode, particles, and now glow/vibrancy
/// too) layer on top of whichever style is active here too — see
/// `LEDCueParameters`.
public struct LEDCuePreviewView: View {
    public var parameters: LEDCueParameters
    public var diameter: CGFloat
    public var lineWidth: CGFloat
    /// Mirrors `RingView.overrideElapsed` exactly — see its doc comment.
    /// Forwarded straight through to the nested `RingView` for
    /// `.continuousAnimation`; used directly (bypassing `TimelineView`) for
    /// every other style via `legacyStyleContent(elapsed:)`.
    public var overrideElapsed: Double? = nil

    /// Backs `.continuousAnimation` only — see the type doc comment. Held
    /// as `@StateObject` (created once, kept across `parameters` changes)
    /// rather than built fresh per render: `RingConfig.init()` does a
    /// synchronous Keychain read and spins up a `VoiceConversationController`,
    /// both wasted work if repeated every time `parameters` changes (or,
    /// worse, every animation frame). `syncAnimationConfig()` copies the
    /// current `parameters` into it instead, on `.onAppear` and whenever
    /// `parameters` changes.
    @StateObject private var animationConfig = RingConfig()

    public init(parameters: LEDCueParameters, diameter: CGFloat = 160, lineWidth: CGFloat = 12, overrideElapsed: Double? = nil) {
        self.parameters = parameters
        self.diameter = diameter
        self.lineWidth = lineWidth
        self.overrideElapsed = overrideElapsed
    }

    /// The particle layer's own field is a bit bigger than the ring itself,
    /// so particles have room to drift and fade before getting clipped —
    /// see the usage note where this is applied below.
    private var particleFieldDiameter: CGFloat { diameter * 1.35 }

    public var body: some View {
        if parameters.style == .continuousAnimation {
            RingView(config: animationConfig, diameter: diameter, overrideElapsed: overrideElapsed)
                .frame(width: diameter, height: diameter)
                .onAppear { syncAnimationConfig() }
                .onChange(of: parameters) { _, _ in syncAnimationConfig() }
        } else if let overrideElapsed {
            // Same reasoning as `RingView.body`'s override branch — a
            // one-shot deterministic snapshot bypasses TimelineView
            // entirely rather than asking it for "the frame at time t".
            legacyStyleContent(elapsed: overrideElapsed)
        } else {
            legacyStyleBody
        }
    }

    /// Copies every field `RingView` reads off `RingConfig` from this cue's
    /// own `parameters` — the same fields Nexus's own Controls
    /// panel edits, so a `.continuousAnimation` cue really can reproduce
    /// anything designed there. `sequencePlaybackEnabled` is forced on
    /// (unlike Nexus's own default of an infinite ambient loop)
    /// so this cue's `holdSeconds`/`fadeOutSeconds`/`loops` — meaningful for
    /// every other style already — stay meaningful for this one too,
    /// instead of silently doing nothing.
    private func syncAnimationConfig() {
        parameters.apply(to: animationConfig)
    }

    /// Every `LEDPatternStyle` case *except* `.continuousAnimation` — the
    /// original hand-rolled renderer, unchanged in substance from before
    /// that case existed.
    private var legacyStyleBody: some View {
        TimelineView(.animation) { timeline in
            legacyStyleContent(elapsed: timeline.date.timeIntervalSinceReferenceDate)
        }
    }

    /// The actual per-frame content, factored out of `legacyStyleBody` so
    /// it can be called directly with a synthetic elapsed time — see
    /// `overrideElapsed`.
    @ViewBuilder
    private func legacyStyleContent(elapsed: Double) -> some View {
        let cycle = max(cycleDuration, 0.2)
        let t = elapsed.truncatingRemainder(dividingBy: cycle)
        let breathing = parameters.scalePulseEnabled
            ? 1 + parameters.scalePulseAmount * sin(elapsed * parameters.scalePulseSpeed * 2 * .pi)
            : 1

        ZStack {
                // Particles sit behind the style content — like corona rays
                // emanating from underneath the ring, not floating in front.
                // Backed by a real CAEmitterLayer (see RingParticleEmitter.swift).
                if parameters.particlesEnabled {
                    // Sized/clipped a bit larger than the ring itself
                    // (`particleFieldDiameter`, not the tight `diameter`)
                    // so particles have real room to drift and fade instead
                    // of hitting a clip edge the instant they leave the
                    // ring's own bounding square. This view is always shown
                    // with some surrounding chrome (see CueExplorerView's
                    // preview), so the modest overflow stays contained.
                    let particleView = RingParticleEmitterView(
                        particlesEnabled: parameters.particlesEnabled,
                        emitterShape: parameters.particleEmitterShape,
                        emitterMode: parameters.particleEmitterMode,
                        emitterSizeMultiplier: parameters.particleEmitterSizeMultiplier,
                        renderMode: parameters.particleRenderMode,
                        birthRate: parameters.particleBirthRate,
                        lifetime: parameters.particleLifetime,
                        lifetimeRange: parameters.particleLifetimeRange,
                        velocity: parameters.particleVelocity,
                        velocityRange: parameters.particleVelocityRange,
                        emissionLongitude: parameters.particleEmissionLongitude,
                        emissionSpread: parameters.particleEmissionSpread,
                        xAcceleration: parameters.particleXAcceleration,
                        yAcceleration: parameters.particleYAcceleration,
                        spin: parameters.particleSpin,
                        spinRange: parameters.particleSpinRange,
                        particleScale: parameters.particleScale,
                        scaleRange: parameters.particleScaleRange,
                        pulseEnabled: parameters.particlePulseEnabled,
                        pulsePeriod: parameters.particlePulsePeriod,
                        blurRadius: parameters.particleBlurRadius,
                        primaryColor: primary(t),
                        secondaryColor: secondary(t),
                        size: particleFieldDiameter,
                        ringRadius: diameter / 2 - lineWidth / 2
                    )
                    // Belt-and-suspenders on top of the in-place update in
                    // RingParticleEmitterView: keying `.id()` to every
                    // particle parameter forces SwiftUI to fully tear down
                    // and recreate the underlying CAEmitterLayer/cells from
                    // scratch whenever any of them change.
                    particleView
                        .id(particleView.parameterSignature)
                        .frame(width: particleFieldDiameter, height: particleFieldDiameter)
                        .clipped()
                        .allowsHitTesting(false)
                }
                aberratedContent(t: t, cycle: cycle)
            }
            .frame(width: diameter, height: diameter)
            .scaleEffect(breathing)
            .blur(radius: parameters.blurRadius)
            .compositingGroup()
            // Same formula as `RingView.body` — see there for why the
            // `.compositingGroup()` above has to come first.
            .saturation(vibrancyMultiplier)
            .contrast(1 + (vibrancyMultiplier - 1) * 0.35)
            .brightness((vibrancyMultiplier - 1) * 0.05)
            .blendMode(parameters.blendMode.swiftUIBlendMode)
    }

    /// `1` when vibrancy is off — see `RingView.vibrancyMultiplier`, which
    /// this mirrors exactly.
    private var vibrancyMultiplier: Double {
        parameters.vibrancyEnabled ? parameters.vibrancyAmount : 1
    }

    private var speed: Double { max(parameters.speed, 0.05) }

    /// Hue-shifted primary/secondary, evaluated against the cue's own
    /// cycle-relative time `t` (rather than unbounded elapsed time) so it
    /// doesn't need threading through every style renderer below — colors
    /// drift within each cycle and reset with it, which reads fine given
    /// most cue cycles are only a couple of seconds long.
    private func hueColor(t: Double, offset: Double) -> Color {
        let raw = (t * parameters.hueShiftSpeed).truncatingRemainder(dividingBy: 1)
        let hue = ((raw < 0 ? raw + 1 : raw) + offset).truncatingRemainder(dividingBy: 1)
        return Color(hue: hue, saturation: 0.85, brightness: 1)
    }

    private func primary(_ t: Double) -> Color {
        parameters.hueShiftEnabled ? hueColor(t: t, offset: 0) : Color(hex: parameters.primaryColorHex)
    }

    private func secondary(_ t: Double) -> Color {
        parameters.hueShiftEnabled ? hueColor(t: t, offset: 0.5) : Color(hex: parameters.secondaryColorHex)
    }

    /// How long one full loop of the preview takes, in seconds. Chosen per
    /// style so quick alerts read as quick and multi-second sequences (spin
    /// → solid → fade) have room to breathe before looping.
    private var cycleDuration: Double {
        switch parameters.style {
        case .continuousAnimation:
            // Never actually reached — `body` renders `RingView` directly
            // for this case, bypassing `legacyStyleBody`/`cycleDuration`
            // entirely. Only here to keep this switch exhaustive.
            return 2.0
        case .solid, .off, .notApplicable, .custom:
            return 2.0
        case .earConOnly:
            return 2.0
        case .flash:
            return (1.0 / speed) * 2
        case .quickFlash:
            let single = 0.14
            return Double(max(parameters.flashCount, 1)) * single * 2 + 0.8
        case .ripple:
            return (1.1 / speed) + 0.2
        case .spin, .rainbow:
            // Exactly one revolution / one trip around the color wheel per
            // loop — no trailing pause. A primitive's loop period has to
            // stay `1 / speed` for the timeline's rotation math to mean
            // what it says (see `LEDPatternStyle.spin`).
            return 1 / speed
        case .pulseAccelerate:
            return Self.pulseAccelerateDuration
        case .transitionToSolid:
            return 0.5 + parameters.holdSeconds + 0.5
        case .spinThenSolidFade:
            return (1.1 / speed) + parameters.holdSeconds + parameters.fadeOutSeconds + 0.6
        case .pulseAccelerateThenSolidFade:
            return 2.2 + parameters.holdSeconds + parameters.fadeOutSeconds + 0.6
        case .rainbowThenWhiteFade:
            return (1.5 / speed) + parameters.holdSeconds + parameters.fadeOutSeconds + 0.6
        case .voiceAssistantColor:
            return 2.4 / speed
        }
    }

    /// Universal post-process, same technique as `RingView.aberratedContent`
    /// — three color-isolated, offset, screen-blended copies of whichever
    /// style is active. Doesn't touch any of the 13 style renderers below.
    @ViewBuilder
    private func aberratedContent(t: Double, cycle: Double) -> some View {
        if parameters.chromaticAberrationEnabled {
            let offset = CGFloat(parameters.chromaticAberrationAmount)
            ZStack {
                content(t: t, cycle: cycle)
                    .colorMultiply(.red)
                    .blendMode(.screen)
                    .offset(x: -offset, y: offset * 0.3)
                content(t: t, cycle: cycle)
                    .colorMultiply(.green)
                    .blendMode(.screen)
                    .offset(x: 0, y: -offset * 0.5)
                content(t: t, cycle: cycle)
                    .colorMultiply(.blue)
                    .blendMode(.screen)
                    .offset(x: offset, y: offset * 0.3)
            }
            .compositingGroup()
        } else {
            content(t: t, cycle: cycle)
        }
    }

    @ViewBuilder
    private func content(t: Double, cycle: Double) -> some View {
        switch parameters.style {
        case .continuousAnimation:
            // Never actually reached — see the matching case in
            // `cycleDuration` above.
            EmptyView()
        case .solid:
            ring(opacity: 1, color: primary(t))
        case .off, .notApplicable:
            ring(opacity: 0.06, color: .white)
        case .earConOnly:
            earconGlyph
        case .flash:
            flashView(t: t)
        case .quickFlash:
            quickFlashView(t: t)
        case .ripple:
            rippleView(t: t, cycle: cycle)
        case .spin:
            spinView(t: t)
        case .pulseAccelerate:
            pulseAccelerateRing(t: t)
        case .rainbow:
            rainbowRing(t: t)
        case .transitionToSolid:
            transitionToSolidView(t: t)
        case .spinThenSolidFade:
            spinThenFadeView(t: t)
        case .pulseAccelerateThenSolidFade:
            pulseAccelerateView(t: t)
        case .rainbowThenWhiteFade:
            rainbowFadeView(t: t)
        case .voiceAssistantColor:
            voiceAssistantView(t: t)
        case .custom:
            ring(opacity: 0.5, color: primary(t))
        }
    }

    // MARK: - Shared drawing

    /// Glow now reads `parameters.glowEnabled`/`glowRadius` (the same Glow &
    /// Blend fields Nexus exposes) instead of a hardcoded
    /// radius-10 shadow — every style above shares this one helper, so
    /// turning glow off/tuning its radius affects all of them uniformly.
    private func ring(opacity: Double, color: Color, width: CGFloat? = nil) -> some View {
        let glowRadius = parameters.glowEnabled ? parameters.glowRadius : 0
        return Circle()
            .stroke(color, style: StrokeStyle(lineWidth: width ?? lineWidth, lineCap: .round))
            .opacity(opacity)
            .shadow(color: color.opacity(opacity * 0.7), radius: opacity > 0 ? glowRadius : 0)
    }

    private var earconGlyph: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: diameter * 0.28))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Style renderers

    private func flashView(t: Double) -> some View {
        let period = 1.0 / speed
        let on = t.truncatingRemainder(dividingBy: period) < period / 2
        return ring(opacity: on ? 1 : 0.05, color: primary(t))
    }

    private func quickFlashView(t: Double) -> some View {
        let single = 0.14
        let flashWindow = Double(max(parameters.flashCount, 1)) * single * 2
        let on: Bool
        if t < flashWindow {
            let phase = t.truncatingRemainder(dividingBy: single * 2)
            on = phase < single
        } else {
            on = false
        }
        return ring(opacity: on ? 1 : 0.05, color: primary(t))
    }

    private func rippleView(t: Double, cycle: Double) -> some View {
        let progress = (t / cycle).truncatingRemainder(dividingBy: 1.0)
        return ZStack {
            ForEach(0..<2, id: \.self) { i in
                let offset = Double(i) * 0.5
                let raw = (progress + offset).truncatingRemainder(dividingBy: 1.0)
                let p = MotionEasing.apply(raw, style: parameters.easingStyle, bounce: parameters.springBounce)
                Circle()
                    .stroke(i.isMultiple(of: 2) ? primary(t) : secondary(t), lineWidth: lineWidth * 0.6)
                    .scaleEffect(0.55 + 0.55 * p)
                    .opacity(1 - p)
            }
            ring(opacity: 0.15, color: primary(t), width: lineWidth * 0.4)
        }
    }

    private func transitionToSolidView(t: Double) -> some View {
        let rampIn = 0.5
        let holdEnd = rampIn + parameters.holdSeconds
        let opacity: Double
        if t < rampIn {
            opacity = t / rampIn
        } else if t < holdEnd {
            opacity = 1
        } else {
            opacity = 0.05
        }
        return ring(opacity: max(opacity, 0.05), color: primary(t))
    }

    // MARK: - Primitives
    //
    // One behavior each, defined as a pure function of `t` that keeps
    // running for as long as it's asked to. The composites below are these
    // same functions with a solid hold and a fade appended — written that
    // way round so a fix to how a spin looks lands in both places at once,
    // which the previous copy-per-composite arrangement couldn't promise.

    /// How long the accelerating pulse takes to run its rate ramp before
    /// starting over. Shared with `cycleDuration` so the loop point and the
    /// ramp can't disagree.
    fileprivate static let pulseAccelerateDuration: Double = 2.2

    /// A bright arc travelling around the ring at exactly `speed`
    /// revolutions per second — see `LEDPatternStyle.spin` for why that
    /// rate is fixed rather than tuned.
    ///
    /// The old `spinThenSolidFade` spun three times over `1.1 / speed`
    /// seconds (≈2.7× the nominal rate). That was fine while it was one
    /// baked-in flourish nobody measured, but wrong for a primitive the
    /// timeline counts rotations of.
    private func spinView(t: Double) -> some View {
        let revolutions = t * speed
        let eased = MotionEasing.apply(
            revolutions.truncatingRemainder(dividingBy: 1),
            style: parameters.easingStyle,
            bounce: parameters.springBounce
        )
        let angle = (revolutions.rounded(.down) + eased) * 2 * .pi
        return ZStack {
            Circle().stroke(primary(t).opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(primary(t), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.radians(angle))
        }
        .shadow(color: primary(t).opacity(0.6), radius: parameters.glowEnabled ? parameters.glowRadius : 0)
    }

    /// Breathing pulse that speeds up across each `pulseAccelerateDuration`
    /// ramp, then starts the ramp again.
    private func pulseAccelerateRing(t: Double) -> some View {
        let local = t.truncatingRemainder(dividingBy: Self.pulseAccelerateDuration)
        let progress = local / Self.pulseAccelerateDuration
        let rate = 1.5 + progress * 8
        let value = (sin(local * rate * 2 * .pi) + 1) / 2
        return ring(
            opacity: 0.4 + 0.6 * value,
            color: primary(t),
            width: lineWidth * CGFloat(0.7 + 0.5 * value)
        )
    }

    /// Full trip around the color wheel per `1 / speed` seconds.
    private func rainbowRing(t: Double) -> some View {
        let hue = (t * speed).truncatingRemainder(dividingBy: 1)
        return ring(opacity: 1, color: Color(hue: hue, saturation: 0.85, brightness: 1))
    }

    // MARK: - Composites
    //
    // Each is `primitive for a while → hold solid → fade out`. The phase
    // durations stay exactly what the spec sheet's cues were transcribed
    // against, so every existing cue renders the same as before.

    /// Shared tail for the three primitive-then-settle composites: the
    /// solid hold, then the fade. Returns `nil` while still in the leading
    /// phase, so each caller only has to describe its own beginning.
    private func settleTail(t: Double, phaseEnd: Double, color: Color) -> AnyView? {
        guard t >= phaseEnd else { return nil }
        let holdEnd = phaseEnd + parameters.holdSeconds
        if t < holdEnd {
            return AnyView(ring(opacity: 1, color: color))
        }
        let fadeProgress = parameters.fadeOutSeconds > 0 ? (t - holdEnd) / parameters.fadeOutSeconds : 1
        return AnyView(ring(opacity: max(1 - fadeProgress, 0.05), color: color))
    }

    private func spinThenFadeView(t: Double) -> some View {
        // The original spun 3 times over its `1.1 / speed` window,
        // regardless of speed. `spinView` turns at `speed` rev/sec, so
        // over that window it would otherwise cover only 1.1 revolutions —
        // scaling its clock by `3 / 1.1` restores exactly three, at every
        // speed, while still going through the one spin implementation.
        //
        // Note the factor has no `speed` in it: `spinDuration` already
        // carries the speed dependence, and including it again made the
        // composite turn 3.75x at 0.8 speed and 1.5x at 2.0.
        let spinDuration = 1.1 / speed
        if let tail = settleTail(t: t, phaseEnd: spinDuration, color: primary(t)) { return tail }
        return AnyView(spinView(t: t * (3 / 1.1)))
    }

    private func pulseAccelerateView(t: Double) -> some View {
        if let tail = settleTail(t: t, phaseEnd: Self.pulseAccelerateDuration, color: primary(t)) { return tail }
        return AnyView(pulseAccelerateRing(t: t))
    }

    private func rainbowFadeView(t: Double) -> some View {
        let sweepDuration = 1.5 / speed
        if let tail = settleTail(t: t, phaseEnd: sweepDuration, color: .white) { return tail }
        // Same reasoning as `spinThenFadeView`, and the same shape: the
        // window is `1.5 / speed` and `rainbowRing` travels one hue trip
        // per `1 / speed`, so slowing its clock by 1.5 lands exactly one
        // full trip across the window at any speed.
        return AnyView(rainbowRing(t: t / 1.5))
    }

    private func voiceAssistantView(t: Double) -> some View {
        let phase = t * speed * 2 * .pi
        let gradient = AngularGradient(colors: [primary(t), secondary(t), primary(t)], center: .center)
        return Circle()
            .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.radians(phase))
            .shadow(color: primary(t).opacity(0.5), radius: parameters.glowEnabled ? parameters.glowRadius : 0)
    }

    // Particle rendering (all 3 emission styles) has moved to a real
    // CAEmitterLayer — see RingParticleEmitter.swift / RingParticleEmitterView.swift.
}
