import SwiftUI

/// A saved snapshot of a `RingConfig` — "an animation you like," bookmarked
/// from Nexus so you can come back to it later or hand it to a
/// teammate (see `RingPresetStore` and `SavedPresetsView`).
///
/// Deliberately excludes a few `RingConfig` properties that aren't really
/// part of "the animation" itself: `previewDiameter` (a preview-window
/// sizing knob, not animation-specific — same reasoning `LEDCueParameters`
/// already uses by omitting it), the background staging image/dim amount
/// (a manual reference photo for the preview, not the ring), and every
/// voice-reactive/ElevenLabs field (a live connection setting, not an
/// animation — and `elevenLabsAPIKey` is a real credential that must never
/// end up in a file you hand someone else). What's left is exactly what
/// `RingView` needs to render the animation the same way on another
/// machine.
///
/// Colors are stored as hex strings via `Color(hex:)`/`.hexString`
/// (`Support/Color+Hex.swift`) since `Color` itself isn't `Codable` — the
/// same convention `LEDCueParameters` already uses, which this type mirrors
/// closely on purpose.
/// `Sendable`: a plain value type of `Codable` scalars and enums —
/// the same conformance `LEDCueParameters` already carries for the same
/// reason. Needed so a snapshot can be captured into the deferred
/// main-queue apply in `TimelinePlayer.prepareForPlayback`.
public struct RingPreset: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var createdAt: Date

    public var animationType: RingAnimationType
    public var patternStyle: LEDPatternStyle?
    public var flashCount: Int
    public var speed: Double
    public var lineWidth: Double
    public var trailFraction: Double
    public var chasingFillStyle: ChasingFillStyle
    public var diodeCount: Double
    /// Optional for the same reason `additionalColorHexes` is (see its doc
    /// comment): synthesized `Decodable` won't fill in a missing key for a
    /// plain defaulted property, so a saved-presets.json written before
    /// these existed would throw `keyNotFound`. `nil` means the defaults —
    /// `.steady` and 2.0.
    public var diodeShape: DiodeShape?
    public var diodeColorMode: DiodeColorMode?
    /// See `RingConfig.smoothingEnabled`. Optional like its neighbours so a
    /// preset saved before smoothing existed still decodes — and decodes to
    /// the hardware-exact render it was saved as.
    public var smoothingEnabled: Bool?
    /// See `RingConfig.smoothingSpread`.
    public var smoothingSpread: Double?
    /// See `RingConfig.smoothingTrail`.
    public var smoothingTrail: Double?
    /// See `RingConfig.smoothingFluidTime`.
    public var smoothingFluidTime: Bool?
    /// See `RingConfig.firmwareLevelField`. Optional like its neighbours so
    /// presets written before it decode unchanged.
    public var firmwareLevelField: FirmwareLevelField?
    /// See `RingConfig.firmwarePatternStream`.
    public var firmwarePatternStream: String?
    /// See `RingConfig.firmwarePatternStreamOffset`.
    public var firmwarePatternStreamOffset: Double?
    public var rippleDropCount: Double?
    public var rippleDecay: Double?
    public var rippleLife: Double?
    public var rippleSeed: Double?
    public var loopSeconds: Double?
    public var diodeFloor: Double?
    public var firmwareTickMs: Double?
    public var diodeScale: Double?
    public var diodeGap: Double?
    public var bloomCount: Double?
    public var bloomBase: Double?
    public var bloomSoftness: Double?
    public var diodeModeEnabled: Bool?
    public var blinkPattern: BlinkPattern?
    public var blinkRate: Double?

    public var primaryColorHex: String
    public var secondaryColorHex: String
    /// Optional (not just defaulted) on purpose: synthesized `Decodable`
    /// only auto-fills a *missing* JSON key for `Optional` properties, not
    /// ones with a plain default value — so this has to be `[String]?`,
    /// not `[String] = []`, for a saved-presets.json written before this
    /// field existed to still decode instead of throwing `keyNotFound`.
    /// `nil` and `[]` both mean "no extra colors" everywhere this is read.
    public var additionalColorHexes: [String]?

    public var glowEnabled: Bool
    public var glowRadius: Double
    public var vibrancyEnabled: Bool
    public var vibrancyAmount: Double

    public var easingStyle: EasingStyle
    public var springBounce: Double
    public var scalePulseEnabled: Bool
    public var scalePulseAmount: Double
    public var scalePulseSpeed: Double
    public var hueShiftEnabled: Bool
    public var hueShiftSpeed: Double
    public var blurRadius: Double
    public var blendMode: RingBlendMode
    public var chromaticAberrationEnabled: Bool
    public var chromaticAberrationAmount: Double

    public var particlesEnabled: Bool
    public var particleEmitterShape: ParticleEmitterShape
    public var particleEmitterMode: ParticleEmitterMode
    public var particleEmitterSizeMultiplier: Double
    public var particleRenderMode: ParticleRenderMode
    public var particleBirthRate: Double
    public var particleLifetime: Double
    public var particleLifetimeRange: Double
    public var particleVelocity: Double
    public var particleVelocityRange: Double
    public var particleEmissionLongitude: Double
    public var particleEmissionSpread: Double
    public var particleXAcceleration: Double
    public var particleYAcceleration: Double
    public var particleSpin: Double
    public var particleSpinRange: Double
    public var particleScale: Double
    public var particleScaleRange: Double
    public var particlePulseEnabled: Bool
    public var particlePulsePeriod: Double
    public var particleBlurRadius: Double

    public var sequencePlaybackEnabled: Bool
    /// Optional for the same reason `additionalColorHexes` is (see its doc
    /// comment): synthesized `Decodable` only auto-fills a missing JSON key
    /// for `Optional` properties, so a saved-presets.json written before
    /// fade-in existed would throw `keyNotFound` on a plain defaulted
    /// `Double`. `nil` means "no fade in", same as 0.
    public var fadeInSeconds: Double?
    public var holdSeconds: Double
    public var fadeOutSeconds: Double
    public var loops: Int

    public var glassStyle: GlassStyle
    public var glassTintEnabled: Bool
    public var glassTintColorHex: String
    public var glassInteractive: Bool

    /// Snapshots every relevant knob off a live `RingConfig`.
    public init(id: UUID = UUID(), name: String, createdAt: Date = Date(), config: RingConfig) {
        self.id = id
        self.name = name
        self.createdAt = createdAt

        animationType = config.animationType
        patternStyle = config.patternStyle
        flashCount = config.flashCount
        speed = config.speed
        lineWidth = config.lineWidth
        trailFraction = config.trailFraction
        chasingFillStyle = config.chasingFillStyle
        diodeCount = config.diodeCount
        diodeShape = config.diodeShape
        diodeColorMode = config.diodeColorMode
        smoothingEnabled = config.smoothingEnabled
        smoothingSpread = config.smoothingSpread
        smoothingTrail = config.smoothingTrail
        smoothingFluidTime = config.smoothingFluidTime
        firmwareLevelField = config.firmwareLevelField
        firmwarePatternStream = config.firmwarePatternStream
        firmwarePatternStreamOffset = config.firmwarePatternStreamOffset
        rippleDropCount = config.rippleDropCount
        rippleDecay = config.rippleDecay
        rippleLife = config.rippleLife
        rippleSeed = config.rippleSeed
        loopSeconds = config.loopSeconds
        diodeFloor = config.diodeFloor
        firmwareTickMs = config.firmwareTickMs
        diodeScale = config.diodeScale
        diodeGap = config.diodeGap
        bloomCount = config.bloomCount
        bloomBase = config.bloomBase
        bloomSoftness = config.bloomSoftness
        diodeModeEnabled = config.diodeModeEnabled
        blinkPattern = config.blinkPattern
        blinkRate = config.blinkRate

        primaryColorHex = config.primaryColor.hexString
        secondaryColorHex = config.secondaryColor.hexString
        additionalColorHexes = config.additionalColors.map { $0.hexString }

        glowEnabled = config.glowEnabled
        glowRadius = config.glowRadius
        vibrancyEnabled = config.vibrancyEnabled
        vibrancyAmount = config.vibrancyAmount

        easingStyle = config.easingStyle
        springBounce = config.springBounce
        scalePulseEnabled = config.scalePulseEnabled
        scalePulseAmount = config.scalePulseAmount
        scalePulseSpeed = config.scalePulseSpeed
        hueShiftEnabled = config.hueShiftEnabled
        hueShiftSpeed = config.hueShiftSpeed
        blurRadius = config.blurRadius
        blendMode = config.blendMode
        chromaticAberrationEnabled = config.chromaticAberrationEnabled
        chromaticAberrationAmount = config.chromaticAberrationAmount

        particlesEnabled = config.particlesEnabled
        particleEmitterShape = config.particleEmitterShape
        particleEmitterMode = config.particleEmitterMode
        particleEmitterSizeMultiplier = config.particleEmitterSizeMultiplier
        particleRenderMode = config.particleRenderMode
        particleBirthRate = config.particleBirthRate
        particleLifetime = config.particleLifetime
        particleLifetimeRange = config.particleLifetimeRange
        particleVelocity = config.particleVelocity
        particleVelocityRange = config.particleVelocityRange
        particleEmissionLongitude = config.particleEmissionLongitude
        particleEmissionSpread = config.particleEmissionSpread
        particleXAcceleration = config.particleXAcceleration
        particleYAcceleration = config.particleYAcceleration
        particleSpin = config.particleSpin
        particleSpinRange = config.particleSpinRange
        particleScale = config.particleScale
        particleScaleRange = config.particleScaleRange
        particlePulseEnabled = config.particlePulseEnabled
        particlePulsePeriod = config.particlePulsePeriod
        particleBlurRadius = config.particleBlurRadius

        sequencePlaybackEnabled = config.sequencePlaybackEnabled
        fadeInSeconds = config.fadeInSeconds
        holdSeconds = config.holdSeconds
        fadeOutSeconds = config.fadeOutSeconds
        loops = config.loops

        glassStyle = config.glassStyle
        glassTintEnabled = config.glassTintEnabled
        glassTintColorHex = config.glassTintColor.hexString
        glassInteractive = config.glassInteractive
    }

    /// Applies every saved knob back onto a live `RingConfig` — used to load
    /// this preset into Nexus.
    public func apply(to config: RingConfig) {
        config.animationType = animationType
        config.patternStyle = patternStyle
        config.flashCount = flashCount
        config.speed = speed
        config.lineWidth = lineWidth
        config.trailFraction = trailFraction
        config.chasingFillStyle = chasingFillStyle
        config.diodeCount = diodeCount
        config.diodeShape = diodeShape ?? .round
        config.diodeColorMode = diodeColorMode ?? .perDiode
        config.smoothingEnabled = smoothingEnabled ?? false
        config.smoothingSpread = smoothingSpread ?? 1.1
        config.smoothingTrail = smoothingTrail ?? 0.22
        config.smoothingFluidTime = smoothingFluidTime ?? true
        config.firmwareLevelField = firmwareLevelField
        config.firmwarePatternStream = firmwarePatternStream
        config.firmwarePatternStreamOffset = firmwarePatternStreamOffset ?? 0
        config.rippleDropCount = rippleDropCount ?? 3
        config.rippleDecay = rippleDecay ?? 0.65
        config.rippleLife = rippleLife ?? 5.5
        config.rippleSeed = rippleSeed ?? 42
        config.loopSeconds = loopSeconds ?? 12
        config.diodeFloor = diodeFloor ?? 0
        config.firmwareTickMs = firmwareTickMs ?? 0
        config.diodeScale = diodeScale ?? 1.0
        config.diodeGap = diodeGap ?? 0.12
        config.bloomCount = bloomCount ?? 6
        config.bloomBase = bloomBase ?? 0.6
        config.bloomSoftness = bloomSoftness ?? 0.15
        config.diodeModeEnabled = diodeModeEnabled ?? false
        config.blinkPattern = blinkPattern ?? .steady
        config.blinkRate = blinkRate ?? 2.0

        config.primaryColor = Color(hex: primaryColorHex)
        config.secondaryColor = Color(hex: secondaryColorHex)
        config.additionalColors = (additionalColorHexes ?? []).map { Color(hex: $0) }

        config.glowEnabled = glowEnabled
        config.glowRadius = glowRadius
        config.vibrancyEnabled = vibrancyEnabled
        config.vibrancyAmount = vibrancyAmount

        config.easingStyle = easingStyle
        config.springBounce = springBounce
        config.scalePulseEnabled = scalePulseEnabled
        config.scalePulseAmount = scalePulseAmount
        config.scalePulseSpeed = scalePulseSpeed
        config.hueShiftEnabled = hueShiftEnabled
        config.hueShiftSpeed = hueShiftSpeed
        config.blurRadius = blurRadius
        config.blendMode = blendMode
        config.chromaticAberrationEnabled = chromaticAberrationEnabled
        config.chromaticAberrationAmount = chromaticAberrationAmount

        config.particlesEnabled = particlesEnabled
        config.particleEmitterShape = particleEmitterShape
        config.particleEmitterMode = particleEmitterMode
        config.particleEmitterSizeMultiplier = particleEmitterSizeMultiplier
        config.particleRenderMode = particleRenderMode
        config.particleBirthRate = particleBirthRate
        config.particleLifetime = particleLifetime
        config.particleLifetimeRange = particleLifetimeRange
        config.particleVelocity = particleVelocity
        config.particleVelocityRange = particleVelocityRange
        config.particleEmissionLongitude = particleEmissionLongitude
        config.particleEmissionSpread = particleEmissionSpread
        config.particleXAcceleration = particleXAcceleration
        config.particleYAcceleration = particleYAcceleration
        config.particleSpin = particleSpin
        config.particleSpinRange = particleSpinRange
        config.particleScale = particleScale
        config.particleScaleRange = particleScaleRange
        config.particlePulseEnabled = particlePulseEnabled
        config.particlePulsePeriod = particlePulsePeriod
        config.particleBlurRadius = particleBlurRadius

        config.sequencePlaybackEnabled = sequencePlaybackEnabled
        config.fadeInSeconds = fadeInSeconds ?? 0
        config.holdSeconds = holdSeconds
        config.fadeOutSeconds = fadeOutSeconds
        config.loops = loops

        config.glassStyle = glassStyle
        config.glassTintEnabled = glassTintEnabled
        config.glassTintColor = Color(hex: glassTintColorHex)
        config.glassInteractive = glassInteractive
    }
}
