import SwiftUI
import RealityKit

#if canImport(AppKit)
import AppKit
private typealias NativeColor = NSColor
#else
import UIKit
private typealias NativeColor = UIColor
#endif

/// A real 3D scene: an emissive core, satellites orbiting on tilted
/// planes, RealityKit's particle emitter streaming the palette, and a
/// glass shell over the lot.
///
/// The one experiment that is truly volumetric, and the one to judge
/// against `LabOrbView`, which fakes a sphere in a fragment shader. What
/// this can do that the shader can't: parallax — the satellites pass in
/// front of and behind the core, and the particles have depth. What it
/// costs: a scene graph and a renderer per instance, no `ImageRenderer`,
/// and materials that need real lighting to look like anything (the first
/// bubble, unlit and 30% opaque, was "a lavender circle").
struct LabVolumetricView: View {
    let frame: LabFrame
    @StateObject private var scene = LabVolumetricScene()

    var body: some View {
        let scene = self.scene
        // The scene keeps the subscription, and the subscription must not
        // keep the scene: the tick reaches it weakly.
        let tick: @Sendable () -> Void = { [weak scene] in MainActor.assumeIsolated { scene?.tick() } }
        return RealityView { content in
            for entity in scene.build(frame: frame) { content.add(entity) }
            scene.subscription = content.subscribe(to: SceneEvents.Update.self) { _ in tick() }
        } update: { _ in
            scene.apply(frame: frame)
        }
        .frame(width: frame.diameter, height: frame.diameter)
        .clipShape(Circle())
    }
}

/// The scene itself, separate from the view so `RealityRenderer` can draw
/// it offscreen — the only way to see a RealityKit scene from the command
/// line, and how this one was checked before it was shown.
@MainActor
public final class LabVolumetricScene: ObservableObject {
    private let root = Entity()
    private var core: ModelEntity?
    private var shell: ModelEntity?
    private var glassKey: Double = -1
    private var satellites: [Entity] = []
    private var emitterEntity = Entity()
    var subscription: EventSubscription?
    private var frame: LabFrame?
    /// The camera, exposed for an offscreen renderer's `activeCamera`.
    public private(set) var camera = PerspectiveCamera()

    public init() {}
    private var colorKey: [Color] = []
    private let start = Date()

    // Camera 3 units back, 30° FOV → visible half-height ≈ 0.80.
    private let shellRadius: Float = 0.76

    /// Builds the scene and returns its top-level entities — camera,
    /// lights, and the root everything else hangs from — for the caller
    /// to add to a `RealityView` or a `RealityRenderer`.
    public func build(frame: LabFrame) -> [Entity] {
        self.frame = frame
        let palette = frame.colors.map(PerceptualGradient.rgb)
        let primary = palette.first ?? RGB(red: 0.3, green: 0.6, blue: 1)
        let secondary = palette.count > 1 ? palette[1] : primary

        camera.camera.fieldOfViewInDegrees = 30
        camera.position = [0, 0, 3]

        let key = DirectionalLight()
        key.light.intensity = 3000
        key.look(at: .zero, from: [-1.5, 1.8, 2.2], relativeTo: nil)
        let fill = PointLight()
        fill.light.intensity = 40_000
        fill.light.attenuationRadius = 6
        fill.light.color = Self.native(secondary)
        fill.position = [1.2, -0.8, 1.5]

        // Core: lit *and* emissive. Unlit was a flat disc in the offscreen
        // render — no shading, so no sphere. Lit with a satin roughness it
        // takes the key light's falloff and reads as a ball; the emissive
        // term keeps it glowing in its own colour on the dark side.
        let core = ModelEntity(mesh: .generateSphere(radius: shellRadius),
                               materials: [Self.coreMaterial(primary)])
        core.scale = SIMD3(repeating: Float(frame.p("core", .volumetric)))
        self.core = core
        root.addChild(core)

        // No halo sphere. A transparent unlit sphere was tried for the
        // glow RealityKit does not do for us, and rendered as a flat disc
        // behind the core — the same failure as the first bubble, at a
        // smaller size. The glow is the particle cloud instead.

        // Satellites on three tilted orbits, in the secondary colour.
        // The depth cue: they cross in front of and behind the core.
        satellites = (0..<8).map { i in
            let pivot = Entity()
            let tilt = Float(i) * 1.1 + 0.4
            pivot.orientation = simd_quatf(angle: tilt, axis: normalize(SIMD3<Float>(1, 0.2, Float(i) * 0.5)))
            let s = ModelEntity(mesh: .generateSphere(radius: shellRadius * 0.075),
                                materials: [Self.coreMaterial(secondary)])
            s.position = [shellRadius * 0.62, 0, 0]
            pivot.addChild(s)
            root.addChild(pivot)
            return pivot
        }

        // Particles: the magic preset, in our colours, born on a sphere
        // round the core and drifting outward. Additive so they glow.
        emitterEntity.components.set(Self.emitter(primary: primary, secondary: secondary, frame: frame))
        root.addChild(emitterEntity)

        // Shell: glass that is *almost not there*. RealityKit's PBR has no
        // Fresnel-driven opacity, so any body opacity is a flat wash over
        // the whole disc — at 30% it was grey milk (checked offscreen).
        // At 6% the body vanishes and what is left is the clearcoat's
        // specular: a highlight and a faint rim, which is what glass is.
        var glass = PhysicallyBasedMaterial()
        glass.baseColor = .init(tint: NativeColor(white: 1, alpha: 0.08))
        glass.roughness = .init(floatLiteral: 0.03)
        glass.metallic = .init(floatLiteral: 0)
        glass.specular = .init(floatLiteral: 1)
        glass.clearcoat = .init(floatLiteral: 1)
        glass.clearcoatRoughness = .init(floatLiteral: 0.03)
        glass.blending = .transparent(opacity: .init(floatLiteral: Float(frame.p("glass", .volumetric))))
        glass.faceCulling = .none
        // The shell must not write depth: when it did, every particle
        // inside it was culled — the offscreen render showed the core and
        // satellites and nothing else, and the same scene without the
        // shell showed the whole cloud.
        glass.writesDepth = false
        // No `ModelSortGroup` on the shell: with one, its post-pass depth
        // hid every particle inside it (offscreen render — nothing but the
        // core and satellites). The core is opaque and sorts itself; the
        // shell is the only transparent model and needs no ordering.
        let shell = ModelEntity(mesh: .generateSphere(radius: shellRadius), materials: [glass])
        self.shell = shell
        root.addChild(shell)

        colorKey = frame.colors
        return [camera, key, fill, root]
    }

    public func apply(frame: LabFrame) {
        self.frame = frame
        if frame.colors != colorKey {
            colorKey = frame.colors
            let palette = frame.colors.map(PerceptualGradient.rgb)
            let primary = palette.first ?? RGB(red: 0.3, green: 0.6, blue: 1)
            let secondary = palette.count > 1 ? palette[1] : primary
            core?.model?.materials = [Self.coreMaterial(primary)]
            emitterEntity.components.set(Self.emitter(primary: primary, secondary: secondary, frame: frame))
        } else if var e = emitterEntity.components[ParticleEmitterComponent.self] {
            e.mainEmitter.birthRate = Self.birthRate(for: frame)
            e.speed = Self.speed(for: frame)
            emitterEntity.components.set(e)
        }
        let glassOpacity = frame.p("glass", .volumetric)
        if glassOpacity != glassKey, let shell, var glass = shell.model?.materials.first as? PhysicallyBasedMaterial {
            glassKey = glassOpacity
            glass.blending = .transparent(opacity: .init(floatLiteral: Float(glassOpacity)))
            shell.model?.materials = [glass]
        }
    }

    /// Advances the motion to the current frame's time. Called per frame
    /// by whoever owns the scene.
    public func tick() {
        guard let frame else { return }
        let t = frame.time
        let swell = Float(1 + frame.audio * 0.25) * Float(frame.p("core", .volumetric))
        core?.scale = [swell, swell, swell]
        root.orientation = simd_quatf(angle: Float(t * frame.p("spin", .volumetric)), axis: [0, 1, 0])
        let visible = Int(frame.p("satellites", .volumetric))
        let orbit = frame.p("orbit", .volumetric)
        for (i, pivot) in satellites.enumerated() {
            pivot.isEnabled = i < visible
            let base = pivot.children.first
            let rate = (0.6 + Double(i) * 0.25) * orbit
            base?.position = [
                shellRadius * 0.62 * Float(cos(t * rate)),
                0,
                shellRadius * 0.62 * Float(sin(t * rate)),
            ]
        }
    }

    private static func birthRate(for frame: LabFrame) -> Float {
        Float(frame.p("rate", .volumetric) * (0.4 + frame.intensity * 1.2) + frame.audio * 1000)
    }

    private static func speed(for frame: LabFrame) -> Float {
        Float(frame.p("moteSpeed", .volumetric) * (0.6 + frame.intensity * 0.8) + frame.audio * 0.04)
    }

    /// Starts from `Presets.magic` — which is what supplies a sprite and
    /// sane defaults — and overrides shape, speed, life, size and colour.
    /// Two things learned the hard way, by rendering offscreen: an empty
    /// `ParticleEmitterComponent()` has no sprite and draws nothing at
    /// all, and `stretchFactor` is 0 for round motes — 1 stretches them
    /// along their velocity into hairs too thin to see. The arithmetic
    /// keeps a mote inside the shell for its life: born at 0.3, speed
    /// ≤ 0.18 damped, life ≤ 3.3 s → well under 0.76.
    private static func emitter(primary: RGB, secondary: RGB, frame: LabFrame) -> ParticleEmitterComponent {
        var e = ParticleEmitterComponent.Presets.magic
        e.emitterShape = .sphere
        e.emitterShapeSize = [0.3, 0.3, 0.3]
        e.birthLocation = .surface
        e.birthDirection = .normal
        e.speed = speed(for: frame)
        e.speedVariation = 0.04
        e.mainEmitter.birthRate = birthRate(for: frame)
        e.mainEmitter.lifeSpan = 2.5
        e.mainEmitter.lifeSpanVariation = 0.8
        e.mainEmitter.size = 0.03
        e.mainEmitter.sizeVariation = 0.012
        e.mainEmitter.sizeMultiplierAtEndOfLifespan = 0.3
        e.mainEmitter.stretchFactor = 0
        e.mainEmitter.dampingFactor = 0.25
        e.mainEmitter.noiseStrength = 0.1
        e.mainEmitter.blendMode = .additive
        e.mainEmitter.opacityCurve = .gradualFadeInOut
        e.mainEmitter.color = .evolving(
            start: .single(native(primary)),
            end: .single(native(secondary)))
        return e
    }

    /// Lit, satin, and glowing its own colour on the dark side.
    private static func coreMaterial(_ c: RGB) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: native(c))
        m.roughness = .init(floatLiteral: 0.35)
        m.metallic = .init(floatLiteral: 0)
        m.emissiveColor = .init(color: native(c))
        m.emissiveIntensity = 0.6
        return m
    }

    private static func native(_ c: RGB) -> NativeColor {
        NativeColor(red: c.red, green: c.green, blue: c.blue, alpha: 1)
    }
}
