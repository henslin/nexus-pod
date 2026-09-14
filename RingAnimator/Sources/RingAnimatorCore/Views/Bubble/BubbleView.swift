import SwiftUI
import RealityKit


#if canImport(AppKit)
import AppKit
typealias BubbleNativeColor = NSColor
#else
import UIKit
typealias BubbleNativeColor = UIColor
#endif

/// A glass bubble with a glyph inside — the pod as an object rather than
/// a drawing.
///
/// **Why RealityKit, when everything else here is SwiftUI.** The ring is
/// a 2D thing and SwiftUI + Metal shaders are the right tool for it. The
/// bubble is not: the whole point is that it reads as a *sphere* — light
/// on the near surface, a rim on the far one, the glyph floating inside —
/// and the same scene has to hold up at 62pt in a tab bar and at full
/// screen when the pod grows into a sheet (Chris, 2026-09-14: "we're
/// going ALL IN"). A camera looking at a real object scales for free;
/// a 2D fake of a sphere has to be re-faked at every size.
///
/// **What is in the scene.** Three entities under one root:
/// - `shell`: the bubble — a physically based sphere, nearly transparent,
///   with a hard clearcoat so it takes a specular highlight and a rim
///   from the image-based light. Both faces drawn, so the far side of
///   the bubble shows through as the second, fainter edge a real bubble
///   has.
/// - `aura`: a smaller unlit sphere inside, carrying the ring's own
///   colours as a soft gradient. It turns slowly so the colour inside
///   the bubble drifts rather than sits. This is what makes the bubble
///   *ours* rather than a generic glass ball.
/// - `glyph`: the SF Symbol, as an unlit textured plane at the centre,
///   always facing the camera.
///
/// **Lighting.** No skybox — `RealityViewEnvironment.skybox` would paint
/// a background behind the pod, and the pod has to stay transparent over
/// the tab bar's glass. Instead a generated equirectangular "studio"
/// image (bright above, a highlight band, dark below) is attached as an
/// `ImageBasedLightComponent` that the shell receives. Same lighting,
/// nothing drawn.
///
/// **Motion.** A per-frame `SceneEvents.Update` subscription bobs the
/// bubble gently and turns the aura; voice level, when the ring is voice
/// reactive, swells the bubble the way it swells the ring.
///
/// `ImageRenderer` cannot rasterise a `RealityView`, so a bubble pod has
/// no thumbnail and no PNG export. Accepted for the prototype; if the
/// bubble ships, thumbnails come from `RealityRenderer` offscreen.
public struct BubbleView: View {
    @ObservedObject var config: RingConfig
    /// The bubble's diameter in points. The scene is built so the sphere
    /// fills the view; the caller sizes the view.
    let diameter: CGFloat
    /// 0…1, from whatever is listening — see `RingView`'s `voiceLevel`.
    let voiceLevel: Double

    @StateObject private var scene = BubbleScene()

    public init(config: RingConfig, diameter: CGFloat, voiceLevel: Double = 0) {
        self.config = config
        self.diameter = diameter
        self.voiceLevel = voiceLevel
    }

    public var body: some View {
        RealityView { content in
            scene.build(into: content, config: config)
        } update: { content in
            scene.apply(config: config, voiceLevel: voiceLevel)
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .accessibilityLabel("Bubble, \(config.podGlyph)")
    }
}

/// The scene's entities and the per-frame state that drives them, kept
/// out of the view so `RealityView`'s closures can reach them without
/// rebuilding anything.
@MainActor
final class BubbleScene: ObservableObject {
    private let root = Entity()
    private var shell: ModelEntity?
    private var aura: ModelEntity?
    private var glyph: ModelEntity?
    private var subscription: EventSubscription?

    private var glyphName = ""
    private var colorKey: [Color] = []
    private var level: Double = 0
    private var start = Date()

    // Scene scale: the camera sits 3 units back with a 30° field of view,
    // so the visible half-height at the origin is 3·tan(15°) ≈ 0.80. A
    // shell radius of 0.74 fills the circle with a hair of margin for the
    // rim highlight to breathe.
    private let shellRadius: Float = 0.74

    func build(into content: RealityViewCameraContent, config: RingConfig) {
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 30
        camera.position = [0, 0, 3]
        content.add(camera)

        // Lighting: a studio environment the shell reflects, plus one key
        // light for a crisp specular hit upper-left, where a photographed
        // glass sphere usually has it.
        let ibl = Entity()
        if let env = Self.studioEnvironment() {
            ibl.components.set(ImageBasedLightComponent(source: .single(env), intensityExponent: 0.6))
        }
        content.add(ibl)

        let key = DirectionalLight()
        key.light.intensity = 2500
        key.look(at: .zero, from: [-1.2, 1.6, 2.0], relativeTo: nil)
        content.add(key)

        let shell = ModelEntity(mesh: .generateSphere(radius: shellRadius), materials: [Self.shellMaterial()])
        shell.components.set(ImageBasedLightReceiverComponent(imageBasedLight: ibl))
        self.shell = shell

        let aura = ModelEntity(mesh: .generateSphere(radius: shellRadius * 0.86),
                               materials: [Self.auraMaterial(colors: Self.colors(of: config))])
        self.aura = aura

        let glyph = ModelEntity(mesh: .generatePlane(width: shellRadius * 1.1, height: shellRadius * 1.1),
                                materials: [Self.glyphMaterial(named: config.podGlyph)])
        glyph.position.z = 0.05
        self.glyph = glyph

        // Draw order matters for transparency: the glyph and aura are
        // inside the shell, so the shell goes last. RealityKit sorts
        // transparent models back to front by origin, and all three share
        // one — `ModelSortGroup` pins the order instead.
        let group = ModelSortGroup(depthPass: .postPass)
        aura.components.set(ModelSortGroupComponent(group: group, order: 0))
        glyph.components.set(ModelSortGroupComponent(group: group, order: 1))
        shell.components.set(ModelSortGroupComponent(group: group, order: 2))

        root.addChild(aura)
        root.addChild(glyph)
        root.addChild(shell)
        content.add(root)

        glyphName = config.podGlyph
        colorKey = Self.colors(of: config)
        start = Date()

        subscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            self?.tick()
        }
    }

    /// Called from `RealityView`'s `update:` whenever SwiftUI re-renders
    /// the view — colours or glyph changed, or the voice level moved.
    func apply(config: RingConfig, voiceLevel: Double) {
        level = voiceLevel
        if config.podGlyph != glyphName, let glyph {
            glyphName = config.podGlyph
            glyph.model?.materials = [Self.glyphMaterial(named: glyphName)]
        }
        let colors = Self.colors(of: config)
        if colors != colorKey, let aura {
            colorKey = colors
            aura.model?.materials = [Self.auraMaterial(colors: colors)]
        }
    }

    private func tick() {
        let t = Date().timeIntervalSince(start)
        // A slow bob and a slower roll — enough that the bubble is alive
        // when nothing is happening, not enough to notice as motion.
        root.position.y = Float(sin(t * 0.9)) * 0.02
        let swell = Float(1 + level * 0.18)
        root.scale = [swell, swell, swell]
        aura?.orientation = simd_quatf(angle: Float(t * 0.25), axis: normalize(SIMD3<Float>(0.3, 1, 0.15)))
    }

    // MARK: - Materials

    private static func shellMaterial() -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: BubbleNativeColor(white: 1, alpha: 0.10))
        m.roughness = .init(floatLiteral: 0.04)
        m.metallic = .init(floatLiteral: 0)
        m.specular = .init(floatLiteral: 1)
        m.clearcoat = .init(floatLiteral: 1)
        m.clearcoatRoughness = .init(floatLiteral: 0.04)
        m.blending = .transparent(opacity: .init(floatLiteral: 0.28))
        m.faceCulling = .none
        return m
    }

    private static func auraMaterial(colors: [Color]) -> UnlitMaterial {
        var m = UnlitMaterial()
        if let texture = gradientTexture(colors: colors) {
            m.color = .init(tint: .white, texture: .init(texture))
        } else {
            m.color = .init(tint: BubbleNativeColor(colors.first ?? .blue))
        }
        m.blending = .transparent(opacity: .init(floatLiteral: 0.55))
        return m
    }

    private static func glyphMaterial(named name: String) -> UnlitMaterial {
        var m = UnlitMaterial()
        if let texture = symbolTexture(named: name) {
            m.color = .init(tint: .white, texture: .init(texture))
        } else {
            m.color = .init(tint: .clear)
        }
        m.blending = .transparent(opacity: .init(floatLiteral: 1))
        return m
    }

    private static func colors(of config: RingConfig) -> [Color] {
        [config.primaryColor, config.secondaryColor] + config.additionalColors
    }

    // MARK: - Textures

    /// The glyph, rendered white on clear at 256pt. `ImageRenderer` is
    /// the one symbol rasteriser that exists on both platforms.
    private static func symbolTexture(named name: String) -> TextureResource? {
        let renderer = ImageRenderer(content:
            Image(systemName: name)
                .resizable()
                .scaledToFit()
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .padding(24)
                .frame(width: 256, height: 256)
        )
        renderer.scale = 2
        guard let cg = renderer.cgImage else { return nil }
        return try? TextureResource(image: cg, options: .init(semantic: .color))
    }

    /// The ring's colours as a vertical perceptual sweep, wrapped round
    /// the aura sphere. 8×64 is plenty — it is a gradient, not a picture.
    private static func gradientTexture(colors: [Color]) -> TextureResource? {
        let sweep = PerceptualGradient.closedSweep(through: colors.map(PerceptualGradient.rgb), count: 63)
        let renderer = ImageRenderer(content:
            LinearGradient(colors: sweep, startPoint: .top, endPoint: .bottom)
                .frame(width: 8, height: 64)
        )
        guard let cg = renderer.cgImage else { return nil }
        return try? TextureResource(image: cg, options: .init(semantic: .color))
    }

    /// A small equirectangular studio: bright soft sky, a horizon band,
    /// a dark floor. Enough for a glass sphere to show a rim and a hit.
    private static func studioEnvironment() -> EnvironmentResource? {
        let renderer = ImageRenderer(content:
            ZStack {
                LinearGradient(stops: [
                    .init(color: Color(white: 0.95), location: 0),
                    .init(color: Color(white: 0.55), location: 0.45),
                    .init(color: Color(white: 0.12), location: 0.55),
                    .init(color: Color(white: 0.04), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                // A softbox: one bright rectangle above the horizon, off
                // to the left, so the highlight has a place to be.
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white)
                    .frame(width: 60, height: 24)
                    .blur(radius: 6)
                    .offset(x: -70, y: -24)
            }
            .frame(width: 256, height: 128)
        )
        guard let cg = renderer.cgImage else { return nil }
        return try? EnvironmentResource(equirectangular: cg)
    }
}
