import SwiftUI
import Metal
import MetalKit

/// The feedback simulation behind `LabInkView`: two textures, a compute
/// step that advects the last frame and adds ink, and a tiny render pass
/// that presents the newest. Separate from the view so a harness can
/// step it offscreen and read the texture back — how it was checked.
@MainActor
public final class LabInkSimulation {
    public let device: MTLDevice
    private let queue: MTLCommandQueue
    private let step: MTLComputePipelineState
    private let present: MTLRenderPipelineState
    private var textures: [MTLTexture] = []
    private var index = 0
    /// Simulation clock; `advance(to:)` steps toward a target time.
    public private(set) var time: Double = 0
    public let size: Int

    public init?(size: Int = 384) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = try? device.makeDefaultLibrary(bundle: .module),
              let stepFn = library.makeFunction(name: "inkStep"),
              let step = try? device.makeComputePipelineState(function: stepFn),
              let vs = library.makeFunction(name: "inkVertex"),
              let fs = library.makeFunction(name: "inkFragment") else { return nil }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vs
        desc.fragmentFunction = fs
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        desc.colorAttachments[0].isBlendingEnabled = true
        desc.colorAttachments[0].sourceRGBBlendFactor = .one
        desc.colorAttachments[0].sourceAlphaBlendFactor = .one
        desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        guard let present = try? device.makeRenderPipelineState(descriptor: desc) else { return nil }
        self.device = device
        self.queue = queue
        self.step = step
        self.present = present
        self.size = size
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: size, height: size, mipmapped: false)
        td.usage = [.shaderRead, .shaderWrite]
        td.storageMode = .private
        for _ in 0..<2 {
            guard let t = device.makeTexture(descriptor: td) else { return nil }
            textures.append(t)
        }
    }

    /// The buffer's parameters, in the kernel's struct layout.
    struct Params {
        var time: Float, dt: Float, decay: Float, flowScale: Float, flowSpeed: Float, injectRadius: Float, emitters: Float, audio: Float, orbit: Float, swirl: Float
        var pad: (Float, Float) = (0, 0)
        var colors: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>, SIMD3<Float>, SIMD3<Float>, SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)
    }

    private func params(frame: LabFrame, dt: Double) -> Params {
        let rgb = frame.colors.map(PerceptualGradient.rgb)
        func c(_ i: Int) -> SIMD3<Float> {
            let k = rgb.isEmpty ? RGB(red: 0.3, green: 0.6, blue: 1) : rgb[i % rgb.count]
            return SIMD3(Float(k.red), Float(k.green), Float(k.blue))
        }
        return Params(time: Float(time), dt: Float(dt),
                      decay: Float(frame.p("decay", .ink)),
                      flowScale: Float(frame.p("flowScale", .ink)),
                      flowSpeed: Float(frame.p("flowSpeed", .ink) * (0.6 + frame.intensity * 0.8)),
                      injectRadius: Float(frame.p("radius", .ink)),
                      emitters: Float(frame.p("emitters", .ink)),
                      audio: Float(frame.audio),
                      orbit: Float(frame.p("orbit", .ink)),
                      swirl: Float(frame.p("swirl", .ink)),
                      colors: (c(0), c(1), c(2), c(3), c(4), c(5), c(6), c(7)))
    }

    /// Steps the simulation toward `frame.time`, at most a few substeps
    /// per call so a stall doesn't turn into a burst of work.
    public func advance(to frame: LabFrame) {
        var remaining = frame.time - time
        guard remaining > 0 else { return }
        remaining = min(remaining, 0.1)
        let dt = 1.0 / 60.0
        var substeps = 0
        while remaining > 0.0001, substeps < 4 {
            let d = min(dt, remaining)
            stepOnce(frame: frame, dt: d)
            remaining -= d
            time += d
            substeps += 1
        }
        time = frame.time
    }

    private func stepOnce(frame: LabFrame, dt: Double) {
        guard let cmd = queue.makeCommandBuffer(), let enc = cmd.makeComputeCommandEncoder() else { return }
        var p = params(frame: frame, dt: dt)
        enc.setComputePipelineState(step)
        enc.setTexture(textures[index], index: 0)
        enc.setTexture(textures[1 - index], index: 1)
        enc.setBytes(&p, length: MemoryLayout<Params>.stride, index: 0)
        let w = step.threadExecutionWidth, h = max(1, step.maxTotalThreadsPerThreadgroup / w)
        enc.dispatchThreads(MTLSize(width: size, height: size, depth: 1), threadsPerThreadgroup: MTLSize(width: w, height: h, depth: 1))
        enc.endEncoding()
        cmd.commit()
        index = 1 - index
    }

    public var current: MTLTexture { textures[index] }

    /// Draws the newest buffer into a drawable.
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor,
              let cmd = queue.makeCommandBuffer(), let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(present)
        enc.setFragmentTexture(current, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }

    /// The buffer as an image — for the harness and Save Frame.
    public func snapshot() -> CGImage? {
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: size, height: size, mipmapped: false)
        td.storageMode = .shared
        guard let shared = device.makeTexture(descriptor: td),
              let cmd = queue.makeCommandBuffer(), let blit = cmd.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: current, to: shared)
        blit.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        var half = [UInt16](repeating: 0, count: size * size * 4)
        shared.getBytes(&half, bytesPerRow: size * 8, from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        for i in 0..<(size * size) {
            let r = Float(Float16(bitPattern: half[i * 4])), g = Float(Float16(bitPattern: half[i * 4 + 1]))
            let b = Float(Float16(bitPattern: half[i * 4 + 2]))
            bytes[i * 4] = UInt8(max(0, min(255, r * 255)))
            bytes[i * 4 + 1] = UInt8(max(0, min(255, g * 255)))
            bytes[i * 4 + 2] = UInt8(max(0, min(255, b * 255)))
            bytes[i * 4 + 3] = 255
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

/// Ink, in the Lab: an `MTKView` presenting the simulation, stepped to
/// the Lab's clock on each SwiftUI update so Speed still applies.
struct LabInkView: View {
    let frame: LabFrame

    var body: some View {
        LabInkMetalView(frame: frame)
            .frame(width: frame.diameter, height: frame.diameter)
    }
}

@MainActor
final class LabInkCoordinator: NSObject, MTKViewDelegate {
    let sim = LabInkSimulation()
    var frame: LabFrame?

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated {
            guard let sim, let frame else { return }
            sim.advance(to: frame)
            sim.draw(in: view)
        }
    }
}

@MainActor private func configure(_ view: MTKView, _ c: LabInkCoordinator) {
    view.device = c.sim?.device
    view.delegate = c
    view.colorPixelFormat = .bgra8Unorm
    view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
    view.framebufferOnly = true
    view.preferredFramesPerSecond = 60
    #if canImport(AppKit)
    view.layer?.isOpaque = false
    #else
    view.isOpaque = false
    view.backgroundColor = .clear
    #endif
}

#if canImport(AppKit)
private struct LabInkMetalView: NSViewRepresentable {
    let frame: LabFrame
    func makeCoordinator() -> LabInkCoordinator { LabInkCoordinator() }
    func makeNSView(context: Context) -> MTKView {
        let v = MTKView()
        configure(v, context.coordinator)
        return v
    }
    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.frame = frame
    }
}
#else
private struct LabInkMetalView: UIViewRepresentable {
    let frame: LabFrame
    func makeCoordinator() -> LabInkCoordinator { LabInkCoordinator() }
    func makeUIView(context: Context) -> MTKView {
        let v = MTKView()
        configure(v, context.coordinator)
        return v
    }
    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.frame = frame
    }
}
#endif
