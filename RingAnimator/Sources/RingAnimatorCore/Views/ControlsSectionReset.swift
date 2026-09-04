import SwiftUI

/// Restores one Controls section's parameters to their defaults.
///
/// Defaults come from a freshly constructed `RingConfig` rather than from
/// literals repeated here, so a default changed on the property is a
/// default changed in Reset too — there is no second copy to fall out of
/// step.
///
/// The section-to-fields mapping *is* hand-written, and is the part that
/// can rot: add a knob to `ShapeSection` and it won't be reset by Shape's
/// button until it's listed here. Kept next to the ids `ControlsView` and
/// `UseCaseDetailView` both use so at least the two panels can't disagree
/// with each other, and the ids are matched exhaustively so an unknown one
/// is a visible no-op rather than a silent partial reset.
public enum ControlsSectionReset {

    /// Whether this section has anything to reset. `fidelity` doesn't —
    /// its controls step a firmware pattern down through its fidelity
    /// levels, and "default" for an imported pattern is a meaningless idea.
    public static func isResettable(_ id: String) -> Bool {
        id != "fidelity"
    }

    public static func reset(_ id: String, on config: RingConfig) {
        let d = RingConfig()
        switch id {
        case "color":
            config.primaryColor = d.primaryColor
            config.secondaryColor = d.secondaryColor
            config.additionalColors = d.additionalColors

        case "smoothing":
            config.smoothingEnabled = d.smoothingEnabled
            config.smoothingGradientRing = d.smoothingGradientRing
            config.smoothingSpread = d.smoothingSpread
            config.smoothingTrail = d.smoothingTrail
            config.smoothingFluidTime = d.smoothingFluidTime

        case "animation":
            config.animationType = d.animationType
            config.speed = d.speed
            config.trailFraction = d.trailFraction
            config.chasingFillStyle = d.chasingFillStyle
            config.easingStyle = d.easingStyle
            config.springBounce = d.springBounce
            config.loopSeconds = d.loopSeconds
            config.rippleDropCount = d.rippleDropCount
            config.rippleDecay = d.rippleDecay
            config.rippleLife = d.rippleLife
            config.rippleSeed = d.rippleSeed
            config.bloomCount = d.bloomCount
            config.bloomBase = d.bloomBase
            config.bloomSoftness = d.bloomSoftness
            config.blinkPattern = d.blinkPattern
            config.blinkRate = d.blinkRate

        case "shape":
            config.lineWidth = d.lineWidth
            config.previewDiameter = d.previewDiameter
            config.diodeModeEnabled = d.diodeModeEnabled
            config.diodeCount = d.diodeCount
            config.diodeShape = d.diodeShape
            config.diodeScale = d.diodeScale
            config.diodeGap = d.diodeGap
            config.diodeFloor = d.diodeFloor
            config.diodeColorMode = d.diodeColorMode
            config.firmwareTickMs = d.firmwareTickMs

        case "motion":
            config.scalePulseEnabled = d.scalePulseEnabled
            config.scalePulseAmount = d.scalePulseAmount
            config.scalePulseSpeed = d.scalePulseSpeed
            config.hueShiftEnabled = d.hueShiftEnabled
            config.hueShiftSpeed = d.hueShiftSpeed
            config.blurRadius = d.blurRadius
            config.blendMode = d.blendMode
            config.chromaticAberrationEnabled = d.chromaticAberrationEnabled
            config.chromaticAberrationAmount = d.chromaticAberrationAmount

        case "glow":
            config.glowEnabled = d.glowEnabled
            config.glowRadius = d.glowRadius
            config.vibrancyEnabled = d.vibrancyEnabled
            config.vibrancyAmount = d.vibrancyAmount

        case "particles":
            config.particlesEnabled = d.particlesEnabled
            config.particleEmitterShape = d.particleEmitterShape
            config.particleEmitterMode = d.particleEmitterMode
            config.particleEmitterSizeMultiplier = d.particleEmitterSizeMultiplier
            config.particleRenderMode = d.particleRenderMode
            config.particleBirthRate = d.particleBirthRate
            config.particleLifetime = d.particleLifetime
            config.particleLifetimeRange = d.particleLifetimeRange
            config.particleVelocity = d.particleVelocity
            config.particleVelocityRange = d.particleVelocityRange
            config.particleEmissionLongitude = d.particleEmissionLongitude
            config.particleEmissionSpread = d.particleEmissionSpread
            config.particleXAcceleration = d.particleXAcceleration
            config.particleYAcceleration = d.particleYAcceleration
            config.particleSpin = d.particleSpin
            config.particleSpinRange = d.particleSpinRange
            config.particleScale = d.particleScale
            config.particleScaleRange = d.particleScaleRange
            config.particlePulseEnabled = d.particlePulseEnabled
            config.particlePulsePeriod = d.particlePulsePeriod
            config.particleBlurRadius = d.particleBlurRadius

        case "playback":
            config.sequencePlaybackEnabled = d.sequencePlaybackEnabled
            config.holdSeconds = d.holdSeconds
            config.fadeOutSeconds = d.fadeOutSeconds
            config.loops = d.loops
            config.flashCount = d.flashCount

        case "background":
            config.backgroundImageEnabled = d.backgroundImageEnabled
            config.backgroundImageData = d.backgroundImageData
            config.backgroundDimAmount = d.backgroundDimAmount

        case "glass":
            config.glassStyle = d.glassStyle
            config.glassTintEnabled = d.glassTintEnabled
            config.glassTintColor = d.glassTintColor
            config.glassInteractive = d.glassInteractive

        case "voice":
            // The API key is deliberately not reset: it's a credential the
            // user pasted, stored in the Keychain, and losing it to a
            // mis-click on a section header would be a genuinely annoying
            // thing for a "reset this section" button to do.
            config.voiceReactiveEnabled = d.voiceReactiveEnabled
            config.voiceReactiveSensitivity = d.voiceReactiveSensitivity
            config.voiceDemoModeEnabled = d.voiceDemoModeEnabled

        default:
            break
        }
    }
}
