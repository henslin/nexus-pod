import SwiftUI
import BorderBeamKit
import ThinkingOrbsKit

// Libraries.dev's SwiftUI ports (Vendor/), wrapped as Lab experiments
// with their Studio's control structure on the rail — so theirs and ours
// sit on one stage and can be compared, and so their Border beam can be
// carried by a Morph state beside our edge glow.

// MARK: - Thinking Orbs · Kit (Orb)

struct LabOrbKitView: View {
    let frame: LabFrame

    var body: some View {
        let state = OrbState.allCases[min(Int(frame.p("state", .orbKit)), OrbState.allCases.count - 1)]
        let size: OrbSize = frame.p("size", .orbKit) < 0.5 ? .px64 : .px20
        let theme: OrbTheme = [OrbTheme.auto, .dark, .light][min(Int(frame.p("theme", .orbKit)), 2)]
        ThinkingOrb(state: state, size: size, theme: theme,
                    speed: frame.p("speed", .orbKit) * (0.6 + frame.intensity * 0.8) * (1 + frame.audio * 0.5),
                    displaySize: frame.diameter)
            .frame(width: frame.diameter, height: frame.diameter)
    }
}

// MARK: - Border Beam · Kit (UI)

/// Their beam's parameters from the rail, shared by the lab and the Morph
/// adornment so both read the same knobs.
struct LabBeamSettings {
    let size: BeamSize
    let variant: BeamColorVariant
    let theme: BeamTheme
    let duration: Double?
    let brightness: Double
    let saturation: Double
    let hueRange: Double
    let strength: Double
    let tuning: BeamTuning

    init(frame: LabFrame) {
        let family = Int(frame.p("family", .beamKit))
        let type = Int(frame.p("type", .beamKit))
        size = family == 0 ? [BeamSize.md, .sm, .line][min(type, 2)] : (type == 0 ? .pulseOutside : .pulseInner)
        variant = BeamColorVariant.allCases[min(Int(frame.p("variant", .beamKit)), BeamColorVariant.allCases.count - 1)]
        theme = [BeamTheme.auto, .dark, .light][min(Int(frame.p("theme", .beamKit)), 2)]
        let d = frame.p("duration", .beamKit)
        duration = d > 0 ? d / (0.6 + frame.intensity * 0.8) : nil
        brightness = frame.p("brightness", .beamKit)
        saturation = frame.p("saturation", .beamKit)
        hueRange = frame.p("hueRange", .beamKit)
        strength = frame.p("strength", .beamKit) * (1 + frame.audio * 0.5)
        tuning = BeamTuning(
            glowBoost: frame.p("size", .beamKit),
            strokeOpacity: frame.p("stroke", .beamKit),
            innerOpacity: frame.p("inner", .beamKit),
            bloomOpacity: frame.p("bloom", .beamKit))
    }
}

struct LabBeamKitView: View {
    let frame: LabFrame

    var body: some View {
        let s = LabBeamSettings(frame: frame)
        let w = frame.diameter * 1.4, h = frame.diameter * 0.55
        BorderBeam(size: s.size, colorVariant: s.variant, theme: s.theme, duration: s.duration,
                   borderRadius: frame.p("radius", .beamKit), brightness: s.brightness, saturation: s.saturation,
                   hueRange: s.hueRange, strength: s.strength, tuning: s.tuning) {
            // Their demo card: three lines on a dark slab.
            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 4).fill(.fill.secondary).frame(width: w * 0.45, height: 12)
                RoundedRectangle(cornerRadius: 4).fill(.fill.tertiary).frame(width: w * 0.85, height: 10)
                RoundedRectangle(cornerRadius: 4).fill(.fill.tertiary).frame(width: w * 0.65, height: 10)
            }
            .padding(24)
            .frame(width: w, height: h, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: frame.p("radius", .beamKit), style: .continuous)
                .fill(frame.darkStage ? Color(white: 0.09) : Color(white: 0.98)))
        }
        .frame(width: w + 80, height: h + 80)
    }
}
