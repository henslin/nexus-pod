import SwiftUI
import QuartzCore
import CoreImage
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Real `CAEmitterLayer`/`CAEmitterCell` configuration for the ring's
/// particle layer — the same particle system UIKit/AppKit apps use for
/// confetti, sparks, and ambient effects, rather than hand-rolled SwiftUI
/// shapes driven by a `TimelineView`. Platform-agnostic: both the iOS and
/// macOS hosting views (see `RingParticleEmitterView.swift`) call into
/// these same functions, so the emitter setup only exists in one place.
///
/// There is no preset/style switch here — every value comes straight from
/// `RingConfig`'s (or `LEDCueParameters`') raw Core Animation properties,
/// so what's exposed in the Controls panel is exactly what's driving the
/// emitter, one property at a time.
enum RingParticleEmitter {
    static let primaryCellName = "primary"
    static let secondaryCellName = "secondary"

    /// One cell per alternating color. Built once per host view and then
    /// mutated in place every frame — `CAEmitterLayer` owns and animates
    /// its particles internally, so recreating the cells each frame would
    /// reset every particle's age and restart the whole effect.
    static func makeCell(name: String) -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.name = name
        cell.contents = ParticleDotImage.cgImage
        cell.birthRate = 0
        cell.lifetime = 1
        return cell
    }

    static func configure(layer: CAEmitterLayer, primary: CAEmitterCell, secondary: CAEmitterCell) {
        layer.emitterCells = [primary, secondary]
    }

    /// Called every frame (the parent `RingView`/`LEDCuePreviewView` is
    /// itself driven by a `TimelineView`, so `updateUIView`/`updateNSView`
    /// fires in step with the ring's own animation). All property writes
    /// are wrapped in a disabled-actions transaction so they take effect
    /// immediately without CALayer's default implicit fade/animation
    /// fighting the emitter's own internal particle simulation.
    ///
    /// Takes plain values rather than `RingConfig` directly, since two very
    /// different model types drive particles in this app — `RingConfig`
    /// (the live designer) and `LEDCueParameters` (the Cue Library) — each
    /// already computes its own current primary/secondary `Color` (hue-
    /// shift included) via its own small helper, so the resolved colors are
    /// passed straight in rather than duplicating that formula a third time
    /// here.
    static func update(
        layer: CAEmitterLayer,
        primary: CAEmitterCell,
        secondary: CAEmitterCell,
        particlesEnabled: Bool,
        emitterShape: ParticleEmitterShape,
        emitterMode: ParticleEmitterMode,
        emitterSizeMultiplier: Double,
        renderMode: ParticleRenderMode,
        birthRate: Double,
        lifetime: Double,
        lifetimeRange: Double,
        velocity: Double,
        velocityRange: Double,
        emissionLongitude: Double,
        emissionSpread: Double,
        xAcceleration: Double,
        yAcceleration: Double,
        spin: Double,
        spinRange: Double,
        particleScale: Double,
        scaleRange: Double,
        pulseEnabled: Bool,
        pulsePeriod: Double,
        blurRadius: Double,
        primaryColor: Color,
        secondaryColor: Color,
        size: CGFloat,
        ringRadius: CGFloat
    ) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Force these writes to the render server immediately rather than
        // waiting for the next natural run-loop-triggered flush — without
        // this, live slider drags can visibly lag behind, since SwiftUI's
        // own transaction on the surrounding view hierarchy doesn't
        // necessarily flush at the same cadence as this explicit one.
        defer {
            CATransaction.commit()
            CATransaction.flush()
        }

        layer.emitterPosition = CGPoint(x: size / 2, y: size / 2)
        layer.renderMode = caRenderMode(renderMode)
        layer.emitterShape = caShape(emitterShape)
        layer.emitterMode = caMode(emitterMode)
        let emitterExtent = ringRadius * 2 * CGFloat(max(emitterSizeMultiplier, 0.05))
        layer.emitterSize = CGSize(width: emitterExtent, height: emitterExtent)
        applyBlur(to: layer, radius: blurRadius)

        guard particlesEnabled else {
            primary.birthRate = 0
            secondary.birthRate = 0
            removeBurstPulse(from: layer)
            return
        }

        primary.color = platformCGColor(primaryColor)
        secondary.color = platformCGColor(secondaryColor)

        let rate = Float(max(birthRate, 0))
        let lifetimeF = Float(max(lifetime, 0.05))
        // The dot bitmap is rendered at a fixed 64pt reference size — scale
        // maps the desired on-screen diameter back to that reference.
        let baseScale = CGFloat(max(particleScale, 0.5)) / 64

        for cell in [primary, secondary] {
            cell.birthRate = rate
            cell.lifetime = lifetimeF
            cell.lifetimeRange = Float(max(lifetimeRange, 0))
            cell.velocity = CGFloat(velocity)
            cell.velocityRange = CGFloat(max(velocityRange, 0))
            cell.emissionLongitude = CGFloat(emissionLongitude) * .pi / 180
            cell.emissionRange = CGFloat(max(emissionSpread, 0)) * .pi / 180
            cell.xAcceleration = CGFloat(xAcceleration)
            cell.yAcceleration = CGFloat(yAcceleration)
            cell.spin = CGFloat(spin)
            cell.spinRange = CGFloat(max(spinRange, 0))
            cell.scale = baseScale
            cell.scaleRange = CGFloat(max(scaleRange, 0)) / 64
            cell.scaleSpeed = 0
            cell.alphaSpeed = -1 / lifetimeF
        }

        if pulseEnabled {
            applyBurstPulse(to: layer, cellName: primaryCellName, period: pulsePeriod, peakBirthRate: rate)
            applyBurstPulse(to: layer, cellName: secondaryCellName, period: pulsePeriod, peakBirthRate: rate)
        } else {
            removeBurstPulse(from: layer)
        }
    }

    // MARK: - Raw enum bridging
    //
    // `RingConfig`'s particle enums mirror Apple's CAEmitterLayer enums
    // case-for-case (see MotionEffects.swift) so the Controls panel reads
    // exactly like the real API — these just bridge our `Codable` copies
    // to the actual `CAEmitterLayerEmitterShape`/`EmitterMode`/`RenderMode`
    // values, since Apple's originals aren't `Codable`/`Sendable`.

    // NOTE: CAEmitterLayerEmitterShape/EmitterMode/RenderMode are bridged
    // into Swift as `RawRepresentable` *structs* (backed by NSString
    // constants under the hood), not true `enum`s — despite the dot-syntax
    // (`.circle`, `.outline`, ...) looking exactly like an enum. The
    // compiler can't prove a switch over a struct's static members is
    // exhaustive, so every switch below needs a `default:` — omitting it
    // fails the whole build with "switch must be exhaustive."
    private static func caShape(_ shape: ParticleEmitterShape) -> CAEmitterLayerEmitterShape {
        switch shape {
        case .point: return .point
        case .line: return .line
        case .rectangle: return .rectangle
        case .circle: return .circle
        default: return .circle
        }
    }

    private static func caMode(_ mode: ParticleEmitterMode) -> CAEmitterLayerEmitterMode {
        switch mode {
        case .points: return .points
        case .outline: return .outline
        case .surface: return .surface
        case .volume: return .volume
        default: return .outline
        }
    }

    private static func caRenderMode(_ mode: ParticleRenderMode) -> CAEmitterLayerRenderMode {
        switch mode {
        case .unordered: return .unordered
        case .oldestFirst: return .oldestFirst
        case .oldestLast: return .oldestLast
        case .backToFront: return .backToFront
        case .additive: return .additive
        default: return .unordered
        }
    }

    // MARK: - Pulse (optional birth-rate wave)

    private static func burstAnimationKey(_ cellName: String) -> String { "burstPulse-\(cellName)" }

    /// Re-adding an identical `CABasicAnimation` under the same key every
    /// frame (`update(...)` runs on every `TimelineView` tick) would keep
    /// restarting its clock, so it would never actually complete a pulse —
    /// but never touching it again after creation would leave it stuck
    /// with whatever peak birth rate/duration were live the moment Pulse
    /// was first enabled, ignoring later slider changes. This compares
    /// against what's already playing and only rebuilds the animation
    /// (restarting its phase) when the desired values have actually
    /// drifted, so it stays both stable frame-to-frame and live-tunable.
    private static func applyBurstPulse(to layer: CAEmitterLayer, cellName: String, period: Double, peakBirthRate: Float) {
        let key = burstAnimationKey(cellName)
        let desiredDuration = max(period / 2, 0.05)

        if let existing = layer.animation(forKey: key) as? CABasicAnimation {
            let currentPeak = (existing.toValue as? NSNumber)?.floatValue ?? -1
            let closeEnough = abs(currentPeak - peakBirthRate) < 0.5 && abs(existing.duration - desiredDuration) < 0.02
            if closeEnough { return }
        }

        let keyPath = "emitterCells.\(cellName).birthRate"
        let anim = CABasicAnimation(keyPath: keyPath)
        anim.fromValue = 0
        anim.toValue = peakBirthRate
        anim.duration = desiredDuration
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(anim, forKey: key)
    }

    private static func removeBurstPulse(from layer: CAEmitterLayer) {
        layer.removeAnimation(forKey: burstAnimationKey(primaryCellName))
        layer.removeAnimation(forKey: burstAnimationKey(secondaryCellName))
    }

    // MARK: - Blur
    //
    // CAEmitterCell has no native soft-focus — this is a real CALayer
    // feature instead: a CIGaussianBlur in `layer.filters`, the same
    // mechanism UIKit/AppKit use for layer-backed blur effects, applied to
    // the whole particle layer independent of the ring's own `blurRadius`
    // (which blurs the ring + particles together, after compositing).

    private static func applyBlur(to layer: CAEmitterLayer, radius: Double) {
        guard radius > 0.01, let filter = CIFilter(name: "CIGaussianBlur") else {
            layer.filters = nil
            return
        }
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        layer.filters = [filter]
    }

    // MARK: - Color

    private static func platformCGColor(_ color: Color) -> CGColor {
        #if canImport(AppKit)
        return NSColor(color).cgColor
        #elseif canImport(UIKit)
        return UIColor(color).cgColor
        #else
        return CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        #endif
    }
}
