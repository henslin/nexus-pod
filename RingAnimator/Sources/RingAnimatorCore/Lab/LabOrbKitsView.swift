import SwiftUI

// Three more orbs from the web, brought in natively (Chris, 2026-09-17):
//
//   Matrix Orb   — rareui.com/components/matrixorb. A dot matrix that
//                  breathes, ripples and orbits by state. Their canvas
//                  maths, in a SwiftUI Canvas. Free for personal and
//                  commercial use; attribution appreciated.
//   Voice Orb    — assistant-ui.com/elements/orb. A marbled sphere with
//                  five session states and four palettes. Their GLSL,
//                  in Metal (`labVoiceOrb`). MIT, © 2025 AgentbaseAI.
//   ORB-21       — shadercn.run/docs/components/orbs/orb-21. "Light
//                  diffusing through a cloud": a volumetric ray march.
//                  Shader by XorDev, ported with the author's permission
//                  — NON-COMMERCIAL USE ONLY, with attribution to XorDev.
//                  In Metal (`labOrb21`). shadercn's runtime is MIT.
//
// Each keeps its own state model (theirs), and reads the Lab's clock,
// intensity and audio the way the other kits do.

// MARK: - Matrix Orb (rareui)

/// Their loop's memory: the per-state weights that blend an interrupted
/// change from what's on screen, the amplitude smoother with its attack
/// and release, and the scale spring.
@MainActor
final class LabMatrixOrbRuntime: ObservableObject {
    var weights: [Double] = [1, 0, 0]
    var amplitude: Double = 0
    var scale: Double = 0.88
    var velocity: Double = 0
    var lastTime: Double? = nil

    static let scales: [Double] = [0.88, 1, 0.92]
    static let stiffness = 180.0, damping = 26.0, attack = 0.22, release = 0.08, blend = 0.16

    func advance(to time: Double, state: Int, level: Double) {
        let dt = min(max(0, time - (lastTime ?? time)), 0.05)
        lastTime = time
        let rate = level > amplitude ? Self.attack : Self.release
        amplitude += (level - amplitude) * (1 - pow(1 - rate, dt * 60))
        let step = 1 - pow(1 - Self.blend, dt * 60)
        for s in 0..<3 { weights[s] += ((s == state ? 1 : 0) - weights[s]) * step }
        velocity += (-Self.stiffness * (scale - Self.scales[state]) - Self.damping * velocity) * dt
        scale += velocity * dt
    }
}

struct LabMatrixOrbView: View {
    let frame: LabFrame
    @StateObject private var runtime = LabMatrixOrbRuntime()

    static let orbiters: [(radius: Double, speed: Double, phase: Double, spread: Double)] = [
        (0.62, 2.2, 0, 0.42), (0.4, -1.7, 2.1, 0.36), (0.8, 1.15, 4, 0.34),
    ]

    /// Their built-in envelope — no abs, so no snap at the troughs.
    static func envelope(_ t: Double) -> Double {
        let slow = 0.5 + 0.5 * sin(t * 0.62 + 0.4)
        let fast = 0.5 + 0.5 * sin(t * 1.9 + 1.1)
        return 0.22 + 0.78 * (0.45 + 0.55 * slow) * fast
    }

    static func intensity(state: Int, d: Double, nx: Double, ny: Double, t: Double, amplitude: Double) -> Double {
        switch state {
        case 1:
            let ripple = 0.5 + 0.5 * sin(d * 4.2 - t * 3)
            return 0.32 + amplitude * (0.34 + 0.38 * ripple)
        case 2:
            var heat = 0.0
            for o in orbiters {
                let a = t * o.speed + o.phase
                let dx = nx - cos(a) * o.radius, dy = ny - sin(a) * o.radius
                heat += exp(-(dx * dx + dy * dy) / (o.spread * o.spread))
            }
            return 0.26 + 0.8 * min(1, heat)
        default:
            return 0.62 + 0.12 * sin(t * 1.05 - d * 2.4)
        }
    }

    var body: some View {
        let state = min(2, max(0, Int(frame.p("state", .matrixOrb))))
        let t = frame.time * frame.p("speed", .matrixOrb)
        let auto = frame.p("envelope", .matrixOrb) >= 0.5
        let level = frame.audio > 0.001 ? frame.audio : (auto ? Self.envelope(t) : frame.p("level", .matrixOrb))
        let _ = runtime.advance(to: frame.time, state: state, level: level)
        let grid = max(3, Int(frame.p("dots", .matrixOrb).rounded()))
        let size = frame.diameter * frame.p("size", .matrixOrb)
        let color = frame.p("color", .matrixOrb) < 0.5 ? Color(hex: "#F75001") : (frame.colors.first ?? .orange)
        let half = Double(grid - 1) / 2
        let spacing = (size * 0.74) / Double(grid - 1)
        let maxRadius = spacing * 0.6
        let weights = runtime.weights, amplitude = runtime.amplitude, scale = runtime.scale
        Canvas { ctx, sz in
            let center = CGPoint(x: sz.width / 2, y: sz.height / 2)
            for iy in 0..<grid {
                for ix in 0..<grid {
                    let nx = (Double(ix) - half) / half, ny = (Double(iy) - half) / half
                    let d = hypot(nx, ny)
                    // 1.12, not the square's corner, is what makes the outline round.
                    if d > 1.12 { continue }
                    var blended = 0.0
                    for s in 0..<3 where weights[s] >= 0.001 {
                        blended += weights[s] * Self.intensity(state: s, d: d, nx: nx, ny: ny, t: t, amplitude: amplitude)
                    }
                    let intensity = min(1, max(0, blended))
                    let radius = maxRadius * exp(-d * d * 1.7) * intensity * scale
                    if radius < 0.25 { continue }
                    let x = center.x + (Double(ix) - half) * spacing * scale
                    let y = center.y + (Double(iy) - half) * spacing * scale
                    ctx.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)), with: .color(color))
                }
            }
        }
        .frame(width: frame.diameter, height: frame.diameter)
    }
}

// MARK: - Voice Orb (assistant-ui)

/// Their per-state parameters, eased toward at 0.045 a frame.
struct LabVoiceOrbParams {
    var speed, amplitude, glow, brightness, pulse, saturation: Double
    static let states: [LabVoiceOrbParams] = [
        .init(speed: 0.15, amplitude: 0.04, glow: 0.15, brightness: 0.55, pulse: 0, saturation: 0.7),   // idle
        .init(speed: 0.5, amplitude: 0.1, glow: 0.45, brightness: 0.75, pulse: 1, saturation: 0.9),     // connecting
        .init(speed: 0.4, amplitude: 0.14, glow: 0.5, brightness: 0.85, pulse: 0, saturation: 1),       // listening
        .init(speed: 1.4, amplitude: 0.35, glow: 0.9, brightness: 1, pulse: 0, saturation: 1),          // speaking
        .init(speed: 0.06, amplitude: 0.015, glow: 0.08, brightness: 0.35, pulse: 0, saturation: 0.2),  // muted
    ]
    mutating func ease(toward t: LabVoiceOrbParams, dt: Double) {
        let s = 1 - pow(1 - 0.045, dt * 60)
        speed += (t.speed - speed) * s
        amplitude += (t.amplitude - amplitude) * s
        glow += (t.glow - glow) * s
        brightness += (t.brightness - brightness) * s
        pulse += (t.pulse - pulse) * s
        saturation += (t.saturation - saturation) * s
    }
}

@MainActor
final class LabVoiceOrbRuntime: ObservableObject {
    var params = LabVoiceOrbParams.states[0]
    var lastTime: Double? = nil
    func advance(to time: Double, state: Int) {
        let dt = min(max(0, time - (lastTime ?? time)), 0.05)
        lastTime = time
        params.ease(toward: LabVoiceOrbParams.states[state], dt: dt)
    }
}

struct LabVoiceOrbView: View {
    let frame: LabFrame
    @StateObject private var runtime = LabVoiceOrbRuntime()

    static let variants: [[Color]] = [
        [Color(red: 0.55, green: 0.55, blue: 0.6), Color(red: 0.7, green: 0.7, blue: 0.75), Color(red: 0.4, green: 0.4, blue: 0.45)],
        [Color(red: 0.2, green: 0.5, blue: 1), Color(red: 0.4, green: 0.7, blue: 1), Color(red: 0.1, green: 0.3, blue: 0.8)],
        [Color(red: 0.6, green: 0.3, blue: 1), Color(red: 0.8, green: 0.5, blue: 1), Color(red: 0.4, green: 0.15, blue: 0.8)],
        [Color(red: 0.15, green: 0.75, blue: 0.55), Color(red: 0.3, green: 0.9, blue: 0.7), Color(red: 0.1, green: 0.55, blue: 0.4)],
    ]

    var body: some View {
        let state = min(4, max(0, Int(frame.p("state", .voiceOrb))))
        let _ = runtime.advance(to: frame.time, state: state)
        let p = runtime.params
        // Volume rides on top of the state, as theirs does.
        let vol = min(1, frame.p("volume", .voiceOrb) + frame.audio)
        let variant = Int(frame.p("variant", .voiceOrb))
        let colors: [Color] = variant < Self.variants.count ? Self.variants[variant]
            : [frame.colors.first ?? .blue, frame.colors.count > 1 ? frame.colors[1] : .white, frame.colors.last ?? .blue]
        let time = Float(frame.time * frame.p("speed", .voiceOrb))
        Rectangle()
            .fill(Color.white)
            .frame(width: frame.diameter, height: frame.diameter)
            .visualEffect { content, proxy in
                content.colorEffect(
                    ShaderLibrary.bundle(.module).labVoiceOrb(
                        .float2(proxy.size), .float(time),
                        .float(Float(p.speed + vol * 0.4)), .float(Float(p.amplitude + vol * 0.12)),
                        .float(Float(p.glow + vol * 0.2)), .float(Float(p.brightness)),
                        .float(Float(p.pulse)), .float(Float(p.saturation)),
                        .color(colors[0]), .color(colors[1]), .color(colors[2])
                    )
                )
            }
    }
}

// MARK: - ORB-21 (shadercn · XorDev)

struct LabOrb21View: View {
    let frame: LabFrame

    /// Their state presets: ambient, power, shadow lift — and the palette.
    static let presets: [(ambient: Double, power: Double, lift: Double, light: String, shadow: String)] = [
        (0.12, 1.9, 0.55, "#ffd7a3", "#3a4a8c"),   // idle
        (0.22, 2.15, 0.65, "#e6d4ff", "#3b3f96"),  // thinking
        (0.46, 3.1, 0.95, "#ffb066", "#7a2f6e"),   // speaking
    ]

    var body: some View {
        let state = min(2, max(0, Int(frame.p("state", .orb21))))
        let preset = Self.presets[state]
        let ring = frame.p("palette", .orb21) >= 0.5
        let light = ring ? (frame.colors.first ?? .orange) : Color(hex: preset.light)
        let shadow = ring ? (frame.colors.count > 1 ? frame.colors[1] : .indigo) : Color(hex: preset.shadow)
        let res = frame.p("resolution", .orb21)
        let k = { (id: String) in frame.p(id, .orb21) }
        let knobs: [Float] = [
            k("camDist"), k("focal"), k("radius"), k("scale"), k("churn"), k("threshold"), k("edgeSoft"),
            k("density"), k("absorb"), k("shadowAbsorb"), k("shadowLift") * preset.lift / 0.55, k("aniso"), k("lightSpin"),
            k("power") * preset.power / 1.9, k("ambient") * preset.ambient / 0.12, k("exposure"), k("alphaGain"),
            k("steps"), k("lightSteps"),
        ].map { Float($0) }
        let anim = Float(frame.time * k("speed"))
        // Their volumes: the agent's output turns the light up, your input
        // thickens the cloud — the Lab's audio stands in for whichever the
        // state is.
        let inputVol = Float(state == 0 ? frame.audio : 0)
        let outputVol = Float(state == 2 ? frame.audio + frame.intensity * 0.3 : frame.intensity * 0.3)
        let side = frame.diameter * res
        Rectangle()
            .fill(Color.white)
            .frame(width: side, height: side)
            .visualEffect { content, proxy in
                content.colorEffect(
                    ShaderLibrary.bundle(.module).labOrb21(
                        .float2(proxy.size), .float(anim), .float(inputVol), .float(outputVol),
                        .floatArray(knobs), .color(light), .color(shadow)
                    )
                )
            }
            // Marched at a fraction of the size and scaled up: a cloud
            // forgives it, and the march is the cost.
            .scaleEffect(1 / res)
            .frame(width: frame.diameter, height: frame.diameter)
    }
}
