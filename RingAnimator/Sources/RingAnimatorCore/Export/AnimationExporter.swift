import SwiftUI
import AVFoundation
import VideoToolbox
import ImageIO
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// Renders a `RingConfig`'s animation to an animated GIF and/or a `.mov`
/// movie file.
///
/// The whole thing hinges on one fact about `RingView`: its entire
/// continuous-animation rendering path is a pure function of a single
/// `elapsed: Double` value (see `RingView.continuousAnimationContent(elapsed:)`
/// and `overrideElapsed`) — no accumulated mutable state, no dependency on
/// real wall-clock time beyond that one scalar. That means substituting
/// `frameIndex / fps` for real time reproduces an exact, repeatable frame
/// every time, which is exactly what a deterministic frame-by-frame export
/// needs. The one exception is the particle layer (`RingParticleEmitterView`,
/// a real `CAEmitterLayer` physics simulation) — it can't be seeked or
/// snapshotted deterministically, so `exportConfig(from:)` force-disables it
/// for the duration of the export regardless of the source config's setting.
@MainActor
public enum AnimationExporter {

    public enum Format {
        case gif
        case movie
    }

    /// What fills the frame.
    ///
    /// `.ring` is the pod on its own — the original behaviour, and what a
    /// transparent export is for. `.appUI` renders the phone *screen*:
    /// the chosen tab's screenshot with the live Liquid Glass tab bar and
    /// ring pod composited over it, which is the thing to drop into a
    /// device frame in a deck.
    public enum Canvas: Equatable, Sendable {
        case ring
        /// `device` nil is the bare screen; set, it wraps the screen in the
        /// phone body in that finish.
        case appUI(tab: DemoTab, device: DeviceFinish? = nil)
    }

    /// The phone body's colour. Named after the iPhone 16 Pro finishes
    /// because that's what someone building a deck is matching, and
    /// approximated as flat colours — the body here is the same drawn
    /// rounded rectangle `PhoneMockupView` shows on the canvas, not a
    /// photographic render.
    public enum DeviceFinish: String, CaseIterable, Identifiable, Sendable {
        case blackTitanium = "Black Titanium"
        case naturalTitanium = "Natural Titanium"
        case whiteTitanium = "White Titanium"
        case desertTitanium = "Desert Titanium"

        public var id: String { rawValue }

        public var bodyColor: Color {
            switch self {
            case .blackTitanium: return Color(red: 0.24, green: 0.24, blue: 0.25)
            case .naturalTitanium: return Color(red: 0.76, green: 0.74, blue: 0.71)
            case .whiteTitanium: return Color(red: 0.95, green: 0.94, blue: 0.93)
            case .desertTitanium: return Color(red: 0.76, green: 0.66, blue: 0.57)
            }
        }
    }

    /// The phone screen, in points — the single source of truth for both
    /// this exporter and `PhoneMockupView`'s own mockup, so an exported
    /// frame and what's on the canvas can't drift apart.
    public static let phoneScreenSize = CGSize(width: 402, height: 874)

    /// The point size of a rendered frame for a given canvas.
    public static func canvasSize(_ canvas: Canvas) -> CGSize {
        switch canvas {
        case .ring:
            return CGSize(width: canvasDiameter, height: canvasDiameter)
        case .appUI(_, let device):
            guard device != nil else { return phoneScreenSize }
            return CGSize(
                width: phoneScreenSize.width + phoneBezel * 2,
                height: phoneScreenSize.height + phoneBezel * 2
            )
        }
    }
    /// Matches `PhoneMockupView.screen`: the bar is inset 21pt on each
    /// side and sits 21pt off the bottom.
    private static let tabBarInset: CGFloat = 42
    private static let tabBarBottomPadding: CGFloat = 21
    /// The phone body's bezel, corner radii and Dynamic Island — shared
    /// with `PhoneMockupView.deviceFrame` for the same reason the screen
    /// size is: two definitions of the same phone would drift.
    public static let phoneBezel: CGFloat = 12
    public static let phoneScreenCornerRadius: CGFloat = 44
    public static let phoneBodyCornerRadius: CGFloat = 58
    private static let dynamicIslandSize = CGSize(width: 126, height: 36)

    public enum ExportError: Error, LocalizedError {
        case noFrames
        case gifSetupFailed
        case gifFinalizeFailed
        case movieSetupFailed
        case pixelBufferCreationFailed
        case movieWritingFailed(String)

        public var errorDescription: String? {
            switch self {
            case .noFrames:
                return "There were no frames to export."
            case .gifSetupFailed, .gifFinalizeFailed:
                return "Couldn't write the GIF file."
            case .movieSetupFailed:
                return "Couldn't set up the video writer."
            case .pixelBufferCreationFailed:
                return "Couldn't prepare a video frame."
            case .movieWritingFailed(let reason):
                return "Couldn't write the video: \(reason)"
            }
        }
    }

    /// Fixed rather than user-configurable, at least for now — 30fps and a
    /// crisp-but-not-huge 480pt canvas (rendered at `renderScale` for a
    /// sharp, non-blurry result on Retina displays) cover "share a preview
    /// of this animation" well without a Resolution/FPS picker adding UI
    /// weight to the export sheet for a first pass at this feature.
    public static let fps: Double = 30
    public static let canvasDiameter: CGFloat = 480
    public static let renderScale: CGFloat = 2

    // The same 34pt-pod-in-a-62pt-frame ratio `ContentView.PreviewTab`
    // renders Large Preview at — keeps an exported clip's proportions
    // (ring thickness/glow relative to its round glass backing) consistent
    // with what you see in the app rather than introducing a third ratio.
    private static let podDiameter: CGFloat = 34
    private static let podFrameDiameter: CGFloat = 62

    /// Builds a standalone `RingConfig` snapshot of `source` — via
    /// `RingPreset`, which already knows how to copy every animation-
    /// relevant field — with particles forced off. Never mutates `source`
    /// itself, so exporting never has a visible side effect on whatever's
    /// currently on screen.
    private static func exportConfig(from source: RingConfig) -> RingConfig {
        let snapshot = RingConfig()
        RingPreset(name: "Export Snapshot", config: source).apply(to: snapshot)
        snapshot.particlesEnabled = false
        // The export renders a still, deterministic frame sequence, not a
        // live session — voice reactivity has nothing to react to here.
        snapshot.voiceReactiveEnabled = false
        return snapshot
    }

    /// One loop of the animation at its current speed, clamped to a
    /// sensible range — very slow speeds would otherwise produce an
    /// impractically long/large export, very fast ones a clip too short to
    /// read as looping smoothly.
    public static func naturalLoopDuration(for config: RingConfig) -> TimeInterval {
        if config.sequencePlaybackEnabled {
            // Must match `RingView.sequenceEnvelopeOpacity`'s own envelope
            // length exactly — including `fadeInSeconds`, which was added
            // to the envelope after this function was written. Understating
            // it here silently truncates the exported clip mid-animation.
            let envelope = max(config.fadeInSeconds + config.holdSeconds + config.fadeOutSeconds, 0.1)
            let loops = config.loops > 0 ? config.loops : 1
            return min(max(envelope * Double(loops), 1), 10)
        }
        let oneCycle = 1 / max(config.speed, 0.05)
        return min(max(oneCycle, 1), 8)
    }

    /// One frame's worth of view, for either canvas.
    ///
    /// `elapsed` is the only thing that moves — the property the whole
    /// deterministic export rests on, and the reason the tab bar's pod is
    /// handed a `TimelinePlayback` rather than left to find its own clock.
    /// Passing `nil` gives the *live* view instead, running off its own
    /// clock: that's what the particle recorder needs, and it shares this
    /// definition so a recorded clip and a rendered one can't be laid out
    /// differently.
    @ViewBuilder
    public static func frameView(
        canvas: Canvas,
        config: RingConfig,
        elapsed: Double?,
        opacity: Double = 1,
        colorScheme: ColorScheme,
        transparent: Bool
    ) -> some View {
        let background: Color = transparent ? .clear : (colorScheme == .dark ? .black : .white)
        switch canvas {
        case .ring:
            let outer = canvasDiameter
            ZStack {
                background
                RingView(config: config, diameter: outer * (podDiameter / podFrameDiameter), overrideElapsed: elapsed)
                    .frame(width: outer, height: outer)
                    .opacity(opacity)
            }
            .frame(width: outer, height: outer)
            .environment(\.colorScheme, colorScheme)

        case .appUI(let tab, let device):
            let size = phoneScreenSize
            let screen = ZStack(alignment: .bottom) {
                tab.screenshotImage(dark: colorScheme == .dark)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                // The voice pill is left out on purpose — it's a transient
                // state someone triggers, not part of the resting screen.
                TabBarPreview(
                    config: config,
                    selectedTab: .constant(tab),
                    width: size.width - tabBarInset,
                    playback: elapsed.map { TimelinePlayback(elapsed: $0, opacity: opacity) }
                )
                .padding(.bottom, tabBarBottomPadding)
            }
            .frame(width: size.width, height: size.height)

            if let device {
                let body = canvasSize(.appUI(tab: tab, device: device))
                ZStack {
                    background
                    RoundedRectangle(cornerRadius: phoneBodyCornerRadius, style: .continuous)
                        .fill(device.bodyColor)
                        .frame(width: body.width, height: body.height)
                    screen
                        .clipShape(RoundedRectangle(cornerRadius: phoneScreenCornerRadius, style: .continuous))
                    Capsule()
                        .fill(Color.black)
                        .frame(width: dynamicIslandSize.width, height: dynamicIslandSize.height)
                        .offset(y: -size.height / 2 + 26)
                }
                .frame(width: body.width, height: body.height)
                .environment(\.colorScheme, colorScheme)
            } else {
                // Square-cornered and unclipped on purpose: the bare screen
                // is for dropping into a frame that supplies its own corner
                // mask, and rounding it here would either double up on that
                // or leave four dark notches behind.
                screen
                    .environment(\.colorScheme, colorScheme)
            }
        }
    }

    // MARK: - Frame rendering

    /// Renders `loopCount` repeats of the animation's natural loop as a
    /// flat sequence of opaque `CGImage`s — GIF and the movie encoder below
    /// both consume the same frame array, so rendering only happens once
    /// even when exporting both formats.
    ///
    /// `ImageRenderer` is main-actor-only (it's ultimately driving
    /// AppKit/UIKit rendering under the hood), so this whole loop runs on
    /// the main thread — there's no way to move it to a background queue.
    /// A `Task.yield()` every frame at least lets the run loop interleave
    /// other main-thread work (SwiftUI updating the export sheet's
    /// progress bar, the window staying responsive) between frames instead
    /// of blocking it solid for however long the whole export takes.
    /// `onProgress` is called on the main actor after every frame.
    public static func renderFrames(
        config: RingConfig,
        colorScheme: ColorScheme,
        loopCount: Int,
        transparent: Bool = false,
        canvas: Canvas = .ring,
        onProgress: @MainActor (Double) -> Void = { _ in }
    ) async -> [CGImage] {
        let export = exportConfig(from: config)
        let loopDuration = naturalLoopDuration(for: config)
        let totalDuration = loopDuration * Double(max(loopCount, 1))
        let frameCount = max(Int((totalDuration * fps).rounded()), 1)

        var frames: [CGImage] = []
        frames.reserveCapacity(frameCount)

        for index in 0..<frameCount {
            let elapsed = Double(index) / fps
            let renderer = ImageRenderer(content: frameView(
                canvas: canvas, config: export, elapsed: elapsed, opacity: 1,
                colorScheme: colorScheme, transparent: transparent
            ))
            renderer.scale = renderScale
            renderer.isOpaque = !transparent
            if let cgImage = renderer.cgImage {
                frames.append(cgImage)
            }

            onProgress(Double(index + 1) / Double(frameCount))
            await Task.yield()
        }

        return frames
    }

    /// Renders a whole `RingTimeline` — every step in order, with its own
    /// look, its own phase-continuous rotation, and its own fade envelope.
    ///
    /// Works for the same reason the single-config path above does, just
    /// one level up: `RingTimeline.resolve(at:)` is a pure function of
    /// time, so asking it for `frameIndex / fps` reproduces an exact frame
    /// with no live playhead involved. The per-step `phaseTime` it returns
    /// (rather than the raw timeline clock) is what keeps rotation
    /// continuous across a boundary in the exported file, exactly as it is
    /// on screen — see `RingTimeline.Resolved.phaseTime`.
    ///
    /// Each step's config is built once up front rather than per frame:
    /// `RingConfig.init` reads the Keychain and wires up Combine
    /// pipelines, so constructing one every frame would dominate the
    /// export's runtime for no benefit — within a step the config is a
    /// constant, only `phaseTime` moves.
    public static func renderFrames(
        timeline: RingTimeline,
        colorScheme: ColorScheme,
        loopCount: Int,
        transparent: Bool = false,
        canvas: Canvas = .ring,
        onProgress: @MainActor (Double) -> Void = { _ in }
    ) async -> [CGImage] {
        guard !timeline.isEmpty, timeline.duration > 0 else { return [] }

        // Force wrapping on regardless of the timeline's own setting:
        // `loopCount` is what decides how many passes get rendered here,
        // and a non-looping timeline would otherwise pin to its final
        // frame for every pass after the first.
        var source = timeline
        source.loops = true

        var configs: [UUID: RingConfig] = [:]
        for segment in timeline.segments where configs[segment.id] == nil {
            let config = RingConfig()
            segment.snapshot.apply(to: config)
            // The timeline owns fading (see `TimelineSegment.opacity`);
            // leaving the step's own single-segment envelope on would
            // multiply the two together, same as during live playback.
            config.sequencePlaybackEnabled = false
            configs[segment.id] = exportConfig(from: config)
        }

        let totalDuration = timeline.duration * Double(max(loopCount, 1))
        let frameCount = max(Int((totalDuration * fps).rounded()), 1)

        var frames: [CGImage] = []
        frames.reserveCapacity(frameCount)

        for index in 0..<frameCount {
            let elapsed = Double(index) / fps
            guard
                let resolved = source.resolve(at: elapsed),
                let config = configs[resolved.segment.id]
            else { continue }

            // Against an opaque backdrop a fade reads as "dissolving into
            // the background". Transparent, it becomes real partial alpha
            // — which HEVC carries faithfully and GIF, being 1-bit, rounds
            // to fully-on until the step disappears outright.
            let renderer = ImageRenderer(content: frameView(
                canvas: canvas, config: config, elapsed: resolved.phaseTime,
                opacity: resolved.opacity, colorScheme: colorScheme, transparent: transparent
            ))
            renderer.scale = renderScale
            renderer.isOpaque = !transparent
            if let cgImage = renderer.cgImage {
                frames.append(cgImage)
            }

            onProgress(Double(index + 1) / Double(frameCount))
            await Task.yield()
        }

        return frames
    }

    // MARK: - GIF

    public static func writeGIF(frames: [CGImage], to url: URL) throws {
        guard !frames.isEmpty else { throw ExportError.noFrames }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else {
            throw ExportError.gifSetupFailed
        }

        let fileProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)

        let frameProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]
        ]
        for frame in frames {
            CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw ExportError.gifFinalizeFailed
        }
    }

    // MARK: - Movie

    /// `transparent` switches the codec, not just a flag: H.264 has no
    /// alpha channel at all, so a transparent export is written as HEVC
    /// with alpha (`hvc1` carrying `ContainsAlphaChannel`) instead. That
    /// plays with transparency in QuickTime, Keynote, and `AVPlayer` — so
    /// a clip can be dropped into a real build as a video layer with no
    /// black box around the ring — at roughly H.264-like file sizes,
    /// where ProRes 4444 would be the same picture an order of magnitude
    /// larger. Premultiplied alpha, matching what `ImageRenderer` hands
    /// back.
    public static func writeMovie(frames: [CGImage], to url: URL, transparent: Bool = false) async throws {
        guard let firstFrame = frames.first else { throw ExportError.noFrames }
        let width = firstFrame.width
        let height = firstFrame.height

        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        } catch {
            throw ExportError.movieSetupFailed
        }

        var outputSettings: [String: Any] = [
            AVVideoCodecKey: transparent ? AVVideoCodecType.hevcWithAlpha : AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        if transparent {
            outputSettings[AVVideoCompressionPropertiesKey] = [
                kVTCompressionPropertyKey_AlphaChannelMode as String:
                    kVTAlphaChannelMode_PremultipliedAlpha as String
            ]
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = false

        // BGRA for the alpha path: it's the format the HEVC-with-alpha
        // encoder actually accepts. ARGB stays for the opaque path,
        // where it has always worked.
        let pixelFormat = transparent ? kCVPixelFormatType_32BGRA : kCVPixelFormatType_32ARGB
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: pixelBufferAttributes)

        guard writer.canAdd(input) else { throw ExportError.movieSetupFailed }
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // `requestMediaDataWhenReady`'s callback runs on `queue`, a
            // plain background `DispatchQueue` — not this function's
            // (MainActor) isolation domain. Under Swift 6 strict
            // concurrency a mutable local `var` captured by that callback
            // would need to prove it's safe to mutate off-actor, which the
            // compiler can't do for an ordinary local. `nonisolated(unsafe)`
            // is the correct escape hatch here: the callback is documented
            // to only ever be invoked serially, one call at a time, so
            // there's no actual data race — just nothing in the type
            // system that expresses that guarantee.
            nonisolated(unsafe) var frameIndex = 0
            let queue = DispatchQueue(label: "com.nexusringapp.animation-export")
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    if frameIndex >= frames.count {
                        input.markAsFinished()
                        writer.finishWriting {
                            if writer.status == .completed {
                                continuation.resume()
                            } else {
                                continuation.resume(throwing: ExportError.movieWritingFailed(writer.error?.localizedDescription ?? "unknown error"))
                            }
                        }
                        return
                    }

                    guard let pixelBuffer = pixelBuffer(from: frames[frameIndex], width: width, height: height, transparent: transparent) else {
                        continuation.resume(throwing: ExportError.pixelBufferCreationFailed)
                        return
                    }
                    let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
                    if !adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
                        continuation.resume(throwing: ExportError.movieWritingFailed(writer.error?.localizedDescription ?? "append failed"))
                        return
                    }
                    frameIndex += 1
                }
            }
        }
    }

    nonisolated private static func pixelBuffer(from cgImage: CGImage, width: Int, height: Int, transparent: Bool) -> CVPixelBuffer? {
        var pixelBufferOut: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let format = transparent ? kCVPixelFormatType_32BGRA : kCVPixelFormatType_32ARGB
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, format, attributes as CFDictionary, &pixelBufferOut)
        guard status == kCVReturnSuccess, let pixelBuffer = pixelBufferOut else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        // `noneSkipFirst` discards alpha, which is right for the opaque
        // path and would silently flatten the transparent one.
        let bitmapInfo = transparent
            ? CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            : CGImageAlphaInfo.noneSkipFirst.rawValue
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else { return nil }

        // Clearing matters only when transparent: the buffer comes back
        // with whatever was in it, and an untouched pixel must be
        // transparent rather than garbage.
        if transparent {
            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelBuffer
    }
}
