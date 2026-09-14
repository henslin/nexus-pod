import SwiftUI
import QuartzCore

#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// Core Animation's particle system, emitting from the ring's outline.
///
/// `CAEmitterLayer` is the oldest particle engine on the platform and
/// still the cheapest: the simulation runs in the render server, so the
/// app's main thread does nothing per frame. It draws sprites, not
/// geometry — a small soft dot here — and everything else (sparks,
/// embers, snow, smoke) is the same layer with a different cell.
///
/// Bridged through `NSViewRepresentable`/`UIViewRepresentable` because it
/// is a layer, not a view. `updateNSView` writes the live values in; the
/// layer animates them itself.
struct LabSparksView: View {
    let frame: LabFrame

    var body: some View {
        LabSparksLayerView(frame: frame)
            .frame(width: frame.diameter, height: frame.diameter)
    }
}

@MainActor
private final class SparksHost {
    let emitter = CAEmitterLayer()
    let cell = CAEmitterCell()
    private var colorKey: [Color] = []

    init() {
        cell.contents = Self.dot()
        cell.birthRate = 0
        cell.lifetime = 1.6
        cell.lifetimeRange = 0.8
        cell.velocity = 30
        cell.velocityRange = 25
        cell.emissionRange = .pi * 2
        cell.scale = 0.10
        cell.scaleRange = 0.06
        cell.scaleSpeed = -0.03
        cell.alphaSpeed = -0.6
        cell.spin = 0
        emitter.emitterCells = [cell]
        emitter.emitterShape = .circle
        emitter.emitterMode = .outline
        emitter.renderMode = .additive
    }

    func apply(frame: LabFrame) {
        let side = frame.diameter
        emitter.emitterPosition = CGPoint(x: side / 2, y: side / 2)
        // The ring's own radius within the stage — the diode ring draws
        // at ~72% of the pod; sparks come off that edge.
        let ringDiameter = side * 0.72
        emitter.emitterSize = CGSize(width: ringDiameter, height: ringDiameter)
        cell.birthRate = Float(60 + frame.intensity * 400 + frame.audio * 900)
        cell.velocity = 20 + frame.intensity * 60 + frame.audio * 120
        cell.scale = 0.08 + frame.intensity * 0.06 + frame.audio * 0.05
        if frame.colors != colorKey {
            colorKey = frame.colors
            let rgb = PerceptualGradient.rgb(frame.colors.first ?? .white)
            cell.color = CGColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
            if frame.colors.count > 1 {
                let b = PerceptualGradient.rgb(frame.colors[1])
                cell.redRange = Float(abs(b.red - rgb.red))
                cell.greenRange = Float(abs(b.green - rgb.green))
                cell.blueRange = Float(abs(b.blue - rgb.blue))
            }
        }
    }

    /// A 32pt soft white dot, drawn once. Coloured by the cell.
    private static func dot() -> CGImage? {
        let size = 32
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let colors = [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0)] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return nil }
        let c = CGPoint(x: size / 2, y: size / 2)
        ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(size) / 2, options: [])
        return ctx.makeImage()
    }
}

#if canImport(AppKit)
private struct LabSparksLayerView: NSViewRepresentable {
    let frame: LabFrame

    func makeCoordinator() -> SparksHost { SparksHost() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.addSublayer(context.coordinator.emitter)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.emitter.frame = view.bounds
        context.coordinator.apply(frame: frame)
    }
}
#else
private struct LabSparksLayerView: UIViewRepresentable {
    let frame: LabFrame

    func makeCoordinator() -> SparksHost { SparksHost() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.layer.addSublayer(context.coordinator.emitter)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.emitter.frame = view.bounds
        context.coordinator.apply(frame: frame)
    }
}
#endif
