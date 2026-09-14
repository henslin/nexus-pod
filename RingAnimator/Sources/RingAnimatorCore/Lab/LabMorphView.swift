import SwiftUI

/// Liquid Glass morphing: one glass shape stepping from the pod's circle
/// to a pill, a card, and a sheet-sized panel, and back, with content
/// riding inside.
///
/// This is the pod-to-sheet expansion Chris described (2026-09-14: "the
/// animation might start in the tab circle but expand into a sheet or
/// even full screen"), as the platform does it: the same glass view, its
/// frame and corner radius animated on a spring. Liquid Glass re-renders
/// its refraction and highlights for the shape at every frame of the
/// animation, which is what makes it read as one object growing rather
/// than one view being replaced by another.
///
/// The stage is a function of the Lab's clock (`hold` seconds per
/// state, ping-pong), so it needs no timer and is deterministic.
struct LabMorphView: View {
    let frame: LabFrame
    @ObservedObject var config: RingConfig

    private enum Stage: Int, CaseIterable { case pod, pill, card, sheet }

    private var stage: Stage {
        let hold = max(frame.p("hold", .morph), 0.2)
        let top = Int(frame.p("stages", .morph))          // 1…3
        let period = top * 2                                 // up and back
        let step = Int(frame.time / hold) % period
        let index = step <= top ? step : period - step       // 0…top…0
        return Stage(rawValue: index) ?? .pod
    }

    private var size: CGSize {
        let d = frame.diameter
        switch stage {
        case .pod:   return CGSize(width: 62, height: 62)
        case .pill:  return CGSize(width: min(d * 0.9, 300), height: 62)
        case .card:  return CGSize(width: min(d * 0.9, 320), height: 170)
        case .sheet: return CGSize(width: d, height: d * 0.95)
        }
    }

    private var cornerRadius: CGFloat {
        switch stage {
        case .pod, .pill: return 31
        case .card:       return 28
        case .sheet:      return 36
        }
    }

    var body: some View {
        let spring = Animation.spring(response: frame.p("spring", .morph),
                                      dampingFraction: 1 - frame.p("bounce", .morph) * 0.45)
        ZStack {
            content
        }
        .frame(width: size.width, height: size.height)
        .modifier(LabGlassShape(cornerRadius: cornerRadius, glass: config.glass))
        .animation(spring, value: stage)
        .frame(width: frame.diameter, height: frame.diameter)
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .pod:
            LabHeroView(frame: frame, config: config, diameter: 62)
        case .pill:
            HStack(spacing: 10) {
                LabHeroView(frame: frame, config: config, diameter: 44)
                Text("John arrived home.")
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
        case .card:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    LabHeroView(frame: frame, config: config, diameter: 44)
                    Text("John arrived home.")
                        .font(.system(size: 17, weight: .semibold))
                    Spacer(minLength: 0)
                }
                Text("Front door unlocked at 5:42 PM. Living room lights are on.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(16)
        case .sheet:
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    LabHeroView(frame: frame, config: config, diameter: 56)
                    Text("Nexus")
                        .font(.system(size: 22, weight: .bold))
                    Spacer(minLength: 0)
                }
                Text("John arrived home.")
                    .font(.system(size: 17, weight: .semibold))
                Text("Front door unlocked at 5:42 PM. Living room lights are on. The thermostat is holding 70°.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(20)
        }
    }
}
