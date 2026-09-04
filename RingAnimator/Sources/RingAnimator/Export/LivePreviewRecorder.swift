import SwiftUI
import AppKit
import ScreenCaptureKit
import AVFoundation
import RingAnimatorCore

/// Records the ring *as the window server actually draws it*, so particle
/// animations can be exported at all.
///
/// Everything else in this app exports by rendering frames directly —
/// `AnimationExporter` substitutes `frameIndex / fps` for real time and
/// gets a deterministic image back. Particles can't work that way, and it
/// isn't for want of trying: `CAEmitterLayer` simulates its particles in
/// the render server, and measurement (see the probes in this feature's
/// commit message) shows they are invisible to every in-process capture
/// path — `CALayer.render(in:)` and `NSView.cacheDisplay(in:to:)` both
/// return a frame with the emitter's own sublayers present and not one
/// particle in it, and `CARenderer`'s offscreen path renders nothing at
/// all on this OS. The compositor is the only thing that has ever seen
/// these particles, so the compositor is what has to be asked.
///
/// Hence ScreenCaptureKit against a single window of our own. Two
/// consequences worth knowing before reaching for this:
///
/// - It runs in real time. A 6-second clip takes 6 seconds, where the
///   deterministic path renders as fast as the machine allows. That's why
///   batch export doesn't offer it.
/// - It is a recording, not a render: a dropped frame is a dropped frame.
///
/// What it does keep is transparency — a window with a clear background
/// captured with `backgroundColor = .clear` comes back with a real alpha
/// channel, verified the same way.
@MainActor
enum LivePreviewRecorder {

    enum RecordError: LocalizedError {
        case permissionDenied
        case windowNotFound
        case noFrames

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Screen Recording permission is needed to capture particles. Grant it in System Settings › Privacy & Security › Screen Recording, then try again."
            case .windowNotFound:
                return "Couldn't find the capture window to record."
            case .noFrames:
                return "The recording didn't capture any frames."
            }
        }
    }

    /// Same canvas the deterministic exporter uses, so a recorded clip and
    /// a rendered one are the same size and proportions.
    private static let canvas = AnimationExporter.canvasDiameter
    private static let scale = AnimationExporter.renderScale
    private static let podDiameter: CGFloat = 34
    private static let podFrameDiameter: CGFloat = 62

    static func record(
        config: RingConfig,
        colorScheme: ColorScheme,
        duration: TimeInterval,
        transparent: Bool,
        onProgress: @escaping @MainActor (Double) -> Void = { _ in }
    ) async throws -> [CGImage] {
        let pixelSize = Int(canvas * scale)
        let wanted = max(Int((duration * AnimationExporter.fps).rounded()), 1)

        // A live config: unlike the export path this one keeps particles
        // on — capturing them is the entire point — but voice reactivity
        // still has nothing to react to.
        let live = RingConfig()
        RingPreset(name: "Capture Snapshot", config: config).apply(to: live)
        live.voiceReactiveEnabled = false

        let window = makeWindow(transparent: transparent, colorScheme: colorScheme, config: live)
        defer { window.orderOut(nil) }

        // The window server needs a moment to composite a brand-new window
        // before `SCShareableContent` will list it — without this wait the
        // filter below finds nothing.
        try? await Task.sleep(for: .milliseconds(1500))

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw RecordError.permissionDenied
        }

        let pid = ProcessInfo.processInfo.processIdentifier
        guard let target = content.windows.first(where: {
            $0.owningApplication?.processID == pid && $0.frame.width == canvas
        }) else {
            throw RecordError.windowNotFound
        }

        let configuration = SCStreamConfiguration()
        configuration.width = pixelSize
        configuration.height = pixelSize
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        // Clear regardless of `transparent`: an opaque export gets its
        // backdrop from the window's own content (see `makeWindow`), the
        // same way the rendered path gets it from the view tree.
        configuration.backgroundColor = .clear
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(AnimationExporter.fps))
        configuration.queueDepth = 8

        let collector = FrameCollector(wanted: wanted)
        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: target), configuration: configuration, delegate: nil)
        try stream.addStreamOutput(collector, type: .screen, sampleHandlerQueue: DispatchQueue(label: "com.nexusringapp.particle-capture"))
        try await stream.startCapture()

        // Poll rather than await a continuation from the sample handler:
        // progress has to keep moving while the recording runs, and this
        // is where "6 seconds of clip takes 6 seconds" is spent.
        let deadline = Date().addingTimeInterval(duration + 4)
        while collector.count < wanted && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
            onProgress(min(Double(collector.count) / Double(wanted), 1))
        }
        try? await stream.stopCapture()

        let frames = collector.frames()
        guard !frames.isEmpty else { throw RecordError.noFrames }
        return Array(frames.prefix(wanted))
    }

    /// A real on-screen window, because only on-screen windows get
    /// composited and therefore captured. Borderless windows aren't listed
    /// by `SCShareableContent` at all, so this is `.titled` with the
    /// titlebar hidden — visually borderless, still capturable.
    private static func makeWindow(transparent: Bool, colorScheme: ColorScheme, config: RingConfig) -> NSWindow {
        let ringDiameter = canvas * (podDiameter / podFrameDiameter)
        let background: Color = transparent ? .clear : (colorScheme == .dark ? .black : .white)

        let content = ZStack {
            background
            RingView(config: config, diameter: ringDiameter)
                .frame(width: canvas, height: canvas)
        }
        .frame(width: canvas, height: canvas)
        .environment(\.colorScheme, colorScheme)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: canvas, height: canvas),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isOpaque = false
        window.backgroundColor = .clear
        // A shadow would be composited into the captured frame as a grey
        // halo in the corners of an otherwise transparent export.
        window.hasShadow = false
        window.isMovableByWindowBackground = false
        window.level = .floating
        window.contentView = NSHostingView(rootView: content)
        window.center()
        window.orderFront(nil)
        return window
    }
}

/// Copies each captured buffer into a `CGImage` on the capture queue.
///
/// The copy isn't optional: ScreenCaptureKit recycles its pixel buffers,
/// so holding one past the callback hands back whatever was drawn later.
private final class FrameCollector: NSObject, SCStreamOutput, @unchecked Sendable {
    private let lock = NSLock()
    private var images: [CGImage] = []
    private let wanted: Int

    init(wanted: Int) {
        self.wanted = wanted
    }

    var count: Int {
        lock.withLock { images.count }
    }

    func frames() -> [CGImage] {
        lock.withLock { images }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, count < wanted,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let image = Self.image(from: buffer) else { return }
        lock.withLock { images.append(image) }
    }

    private static func image(from buffer: CVPixelBuffer) -> CGImage? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard let context = CGContext(
            data: base,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        // `makeImage` copies, which is what detaches this frame from the
        // buffer ScreenCaptureKit is about to reuse.
        return context.makeImage()
    }
}
