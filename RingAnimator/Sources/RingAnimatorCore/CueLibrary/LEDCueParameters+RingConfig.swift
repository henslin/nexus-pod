import SwiftUI

public extension LEDCueParameters {

    /// Copies this cue into a `RingConfig`, which is the form every preview
    /// surface in the app takes.
    ///
    /// It used to be private to `LEDCuePreviewView`, where it existed only
    /// so a `.continuousAnimation` cue could be handed to `RingView`. It's
    /// public now because the Cue Library's own pane renders through
    /// `RingStage` like everything else, and the stage speaks `RingConfig`.
    /// One conversion, in one place, rather than a second one written to
    /// look like this one.
    ///
    /// `patternStyle` carries the cue's style across, which is what lets a
    /// non-continuous cue survive the trip: `RingView` reads it, and hands
    /// the work straight back to `LEDCuePreviewView` with parameters rebuilt
    /// from the config (see `RingView.patternStyleBody`). `.continuousAnimation`
    /// is treated as "no override" at that end, so setting it unconditionally
    /// here is safe.
    ///
    /// `sequencePlaybackEnabled` is forced on, unlike Nexus's own default of
    /// an infinite ambient loop, so this cue's hold/fade/loops — meaningful
    /// for every other style already — stay meaningful here too instead of
    /// silently doing nothing.
    func apply(to config: RingConfig) {
        config.patternStyle = style
        config.flashCount = flashCount
        config.animationType = self.animationType
        config.speed = self.speed
        // Only for `.continuousAnimation`. That's the one style whose ring
        // stroke really is the cue's own — every other style takes its
        // `lineWidth` as a separate `LEDCuePreviewView` init parameter
        // precisely because it's "meant to vary with the surrounding
        // chrome size, not the cue itself" (see `LEDCueParameters.lineWidth`).
        //
        // Copying it regardless made the pattern styles about three times
        // too thick. `RingView` reads `config.lineWidth` as *pod-relative*
        // and multiplies by `size / referenceDiameter`, so the cue's 12 —
        // authored against a ~160pt preview — became a 39pt stroke on a
        // 190pt ring. Leaving `RingConfig`'s own default gives these the
        // same proportions the pod, the mockup and Nexus's preview all use,
        // which is the point of sharing a stage.
        if style == .continuousAnimation {
            config.lineWidth = self.lineWidth
        }
        config.trailFraction = self.trailFraction
        config.chasingFillStyle = self.chasingFillStyle
        config.diodeCount = self.diodeCount
        config.diodeShape = self.diodeShape ?? .round
        config.diodeColorMode = self.diodeColorMode ?? .perDiode
        config.rippleDropCount = self.rippleDropCount ?? 3
        config.rippleDecay = self.rippleDecay ?? 0.65
        config.rippleLife = self.rippleLife ?? 5.5
        config.rippleSeed = self.rippleSeed ?? 42
        config.loopSeconds = self.loopSeconds ?? 12
        config.diodeFloor = self.diodeFloor ?? 0
        config.firmwareTickMs = self.firmwareTickMs ?? 0
        config.diodeModeEnabled = self.diodeModeEnabled ?? false
        config.diodeScale = self.diodeScale ?? 1.0
        config.diodeGap = self.diodeGap ?? 0.12
        config.blinkPattern = self.blinkPattern ?? .steady
        config.blinkRate = self.blinkRate ?? 2.0
        config.bloomCount = self.bloomCount ?? 6
        config.bloomBase = self.bloomBase ?? 0.6
        config.bloomSoftness = self.bloomSoftness ?? 0.15
        config.primaryColor = Color(hex: self.primaryColorHex)
        config.secondaryColor = Color(hex: self.secondaryColorHex)
        config.glowEnabled = self.glowEnabled
        config.glowRadius = self.glowRadius
        config.vibrancyEnabled = self.vibrancyEnabled
        config.vibrancyAmount = self.vibrancyAmount
        config.easingStyle = self.easingStyle
        config.springBounce = self.springBounce
        config.scalePulseEnabled = self.scalePulseEnabled
        config.scalePulseAmount = self.scalePulseAmount
        config.scalePulseSpeed = self.scalePulseSpeed
        config.hueShiftEnabled = self.hueShiftEnabled
        config.hueShiftSpeed = self.hueShiftSpeed
        config.blurRadius = self.blurRadius
        config.blendMode = self.blendMode
        config.chromaticAberrationEnabled = self.chromaticAberrationEnabled
        config.chromaticAberrationAmount = self.chromaticAberrationAmount
        config.particlesEnabled = self.particlesEnabled
        config.particleEmitterShape = self.particleEmitterShape
        config.particleEmitterMode = self.particleEmitterMode
        config.particleEmitterSizeMultiplier = self.particleEmitterSizeMultiplier
        config.particleRenderMode = self.particleRenderMode
        config.particleBirthRate = self.particleBirthRate
        config.particleLifetime = self.particleLifetime
        config.particleLifetimeRange = self.particleLifetimeRange
        config.particleVelocity = self.particleVelocity
        config.particleVelocityRange = self.particleVelocityRange
        config.particleEmissionLongitude = self.particleEmissionLongitude
        config.particleEmissionSpread = self.particleEmissionSpread
        config.particleXAcceleration = self.particleXAcceleration
        config.particleYAcceleration = self.particleYAcceleration
        config.particleSpin = self.particleSpin
        config.particleSpinRange = self.particleSpinRange
        config.particleScale = self.particleScale
        config.particleScaleRange = self.particleScaleRange
        config.particlePulseEnabled = self.particlePulseEnabled
        config.particlePulsePeriod = self.particlePulsePeriod
        config.particleBlurRadius = self.particleBlurRadius
        config.sequencePlaybackEnabled = true
        config.holdSeconds = self.holdSeconds
        config.fadeOutSeconds = self.fadeOutSeconds
        config.loops = self.loops
    }
}
