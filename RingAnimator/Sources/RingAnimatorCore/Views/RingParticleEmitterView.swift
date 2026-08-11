import SwiftUI
import QuartzCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// SwiftUI-facing wrapper around a real `CAEmitterLayer` — the actual
/// particle system UIKit/AppKit apps use, rather than hand-rolled SwiftUI
/// shapes. `RingView`/`LEDCuePreviewView` are already driven by a
/// `TimelineView`, which re-renders (and so calls `updateUIView`/
/// `updateNSView` below) every frame in step with the rest of the ring, so
/// the emitter's position/color/parameters stay in sync with live slider
/// changes the same way the hand-written particles used to.
///
/// The actual emitter setup lives in `RingParticleEmitter.swift`, shared
/// between both platform branches below so there's exactly one place that
/// configures `CAEmitterCell` properties.
struct RingParticleEmitterView {
    var particlesEnabled: Bool
    var emitterShape: ParticleEmitterShape
    var emitterMode: ParticleEmitterMode
    var emitterSizeMultiplier: Double
    var renderMode: ParticleRenderMode
    var birthRate: Double
    var lifetime: Double
    var lifetimeRange: Double
    var velocity: Double
    var velocityRange: Double
    var emissionLongitude: Double
    var emissionSpread: Double
    var xAcceleration: Double
    var yAcceleration: Double
    var spin: Double
    var spinRange: Double
    var particleScale: Double
    var scaleRange: Double
    var pulseEnabled: Bool
    var pulsePeriod: Double
    var blurRadius: Double
    var primaryColor: Color
    var secondaryColor: Color
    var size: CGFloat
    var ringRadius: CGFloat

    /// In-place mutation of an already-`emitterCells`-assigned
    /// `CAEmitterCell`'s properties turns out not to reliably reach Core
    /// Animation's running particle simulation for every property — some
    /// changes only take effect the next time `emitterCells` itself is
    /// reassigned (which is why a resize, which happens to force SwiftUI to
    /// recreate this representable's underlying view from scratch, made
    /// changes "take"). Rather than mutate cells in place and hope, every
    /// value that a Controls-panel slider can change is folded into this
    /// signature; `updateUIView`/`updateNSView` below compare it against
    /// what was last applied and force a full `emitterCells` reassignment
    /// (see `RingParticleEmitter.configure(...)`) whenever it differs, so
    /// any slider move is guaranteed to actually reach the emitter — at the
    /// cost of restarting the particle population (a brief visible reset)
    /// on that change, rather than silently not applying it at all.
    /// Deliberately excludes `primaryColor`/`secondaryColor`/`size`/
    /// `ringRadius`, which can legitimately change every single frame
    /// (hue-shift, breathing scale, ...) and would otherwise force a
    /// reset-every-frame instead of only on an actual slider move.
    var parameterSignature: String {
        [
            particlesEnabled.description,
            emitterShape.rawValue,
            emitterMode.rawValue,
            "\(emitterSizeMultiplier)",
            renderMode.rawValue,
            "\(birthRate)", "\(lifetime)", "\(lifetimeRange)",
            "\(velocity)", "\(velocityRange)",
            "\(emissionLongitude)", "\(emissionSpread)",
            "\(xAcceleration)", "\(yAcceleration)",
            "\(spin)", "\(spinRange)",
            "\(particleScale)", "\(scaleRange)",
            pulseEnabled.description, "\(pulsePeriod)",
            "\(blurRadius)"
        ].joined(separator: "|")
    }
}

#if canImport(UIKit)
extension RingParticleEmitterView: UIViewRepresentable {
    func makeUIView(context: Context) -> HostView {
        let view = HostView()
        RingParticleEmitter.configure(layer: view.emitterLayer, primary: view.primaryCell, secondary: view.secondaryCell)
        return view
    }

    func updateUIView(_ uiView: HostView, context: Context) {
        // Apply the fresh values to the cells FIRST, then (if anything
        // changed) reassign `emitterCells` so that reassignment snapshots
        // the values just set — not last frame's stale ones. Doing this in
        // the other order (reassign, then mutate) is what made the "reset"
        // trick silently capture old values every time.
        RingParticleEmitter.update(
            layer: uiView.emitterLayer,
            primary: uiView.primaryCell,
            secondary: uiView.secondaryCell,
            particlesEnabled: particlesEnabled,
            emitterShape: emitterShape,
            emitterMode: emitterMode,
            emitterSizeMultiplier: emitterSizeMultiplier,
            renderMode: renderMode,
            birthRate: birthRate,
            lifetime: lifetime,
            lifetimeRange: lifetimeRange,
            velocity: velocity,
            velocityRange: velocityRange,
            emissionLongitude: emissionLongitude,
            emissionSpread: emissionSpread,
            xAcceleration: xAcceleration,
            yAcceleration: yAcceleration,
            spin: spin,
            spinRange: spinRange,
            particleScale: particleScale,
            scaleRange: scaleRange,
            pulseEnabled: pulseEnabled,
            pulsePeriod: pulsePeriod,
            blurRadius: blurRadius,
            primaryColor: primaryColor,
            secondaryColor: secondaryColor,
            size: size,
            ringRadius: ringRadius
        )
        if uiView.lastParameterSignature != parameterSignature {
            RingParticleEmitter.configure(layer: uiView.emitterLayer, primary: uiView.primaryCell, secondary: uiView.secondaryCell)
            uiView.lastParameterSignature = parameterSignature
        }
    }

    final class HostView: UIView {
        override class var layerClass: AnyClass { CAEmitterLayer.self }
        var emitterLayer: CAEmitterLayer { layer as! CAEmitterLayer }
        let primaryCell = RingParticleEmitter.makeCell(name: RingParticleEmitter.primaryCellName)
        let secondaryCell = RingParticleEmitter.makeCell(name: RingParticleEmitter.secondaryCellName)
        var lastParameterSignature = ""

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            // Without this, particles that drift past this view's small
            // frame (which happens by design — that's the whole point of
            // "velocity") aren't cut off at all: CALayer content isn't
            // clipped to a SwiftUI `.frame()` unless the layer itself
            // masks to its own bounds, so stray particles were rendering
            // across the rest of the window instead of just this view.
            clipsToBounds = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}

#elseif canImport(AppKit)
extension RingParticleEmitterView: NSViewRepresentable {
    func makeNSView(context: Context) -> HostView {
        let view = HostView()
        RingParticleEmitter.configure(layer: view.emitterLayer, primary: view.primaryCell, secondary: view.secondaryCell)
        return view
    }

    func updateNSView(_ nsView: HostView, context: Context) {
        // Apply the fresh values to the cells FIRST, then (if anything
        // changed) reassign `emitterCells` so that reassignment snapshots
        // the values just set — not last frame's stale ones. Doing this in
        // the other order (reassign, then mutate) is what made the "reset"
        // trick silently capture old values every time.
        RingParticleEmitter.update(
            layer: nsView.emitterLayer,
            primary: nsView.primaryCell,
            secondary: nsView.secondaryCell,
            particlesEnabled: particlesEnabled,
            emitterShape: emitterShape,
            emitterMode: emitterMode,
            emitterSizeMultiplier: emitterSizeMultiplier,
            renderMode: renderMode,
            birthRate: birthRate,
            lifetime: lifetime,
            lifetimeRange: lifetimeRange,
            velocity: velocity,
            velocityRange: velocityRange,
            emissionLongitude: emissionLongitude,
            emissionSpread: emissionSpread,
            xAcceleration: xAcceleration,
            yAcceleration: yAcceleration,
            spin: spin,
            spinRange: spinRange,
            particleScale: particleScale,
            scaleRange: scaleRange,
            pulseEnabled: pulseEnabled,
            pulsePeriod: pulsePeriod,
            blurRadius: blurRadius,
            primaryColor: primaryColor,
            secondaryColor: secondaryColor,
            size: size,
            ringRadius: ringRadius
        )
        if nsView.lastParameterSignature != parameterSignature {
            RingParticleEmitter.configure(layer: nsView.emitterLayer, primary: nsView.primaryCell, secondary: nsView.secondaryCell)
            nsView.lastParameterSignature = parameterSignature
        }
    }

    final class HostView: NSView {
        let primaryCell = RingParticleEmitter.makeCell(name: RingParticleEmitter.primaryCellName)
        let secondaryCell = RingParticleEmitter.makeCell(name: RingParticleEmitter.secondaryCellName)
        var emitterLayer: CAEmitterLayer { layer as! CAEmitterLayer }
        var lastParameterSignature = ""

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            // Same reasoning as the iOS branch's `clipsToBounds` — NSView
            // has no equivalent flag, so it's set directly on the backing
            // layer (which here *is* the CAEmitterLayer itself).
            layer?.masksToBounds = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func makeBackingLayer() -> CALayer {
            CAEmitterLayer()
        }
    }
}
#endif
