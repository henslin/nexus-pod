import SwiftUI
import AVFoundation
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
        onProgress: @MainActor (Double) -> Void = { _ in }
    ) async -> [CGImage] {
        let export = exportConfig(from: config)
        let loopDuration = naturalLoopDuration(for: config)
        let totalDuration = loopDuration * Double(max(loopCount, 1))
        let frameCount = max(Int((totalDuration * fps).rounded()), 1)
        let outerDiameter = canvasDiameter
        let ringDiameter = outerDiameter * (podDiameter / podFrameDiameter)
        let background: Color = colorScheme == .dark ? .black : .white

        var frames: [CGImage] = []
        frames.reserveCapacity(frameCount)

        for index in 0..<frameCount {
            let elapsed = Double(index) / fps
            let frameView = ZStack {
                background
                RingView(config: export, diameter: ringDiameter, overrideElapsed: elapsed)
                    .frame(width: outerDiameter, height: outerDiameter)
            }
            .frame(width: outerDiameter, height: outerDiameter)
            .environment(\.colorScheme, colorScheme)

            let renderer = ImageRenderer(content: frameView)
            renderer.scale = renderScale
            // Opaque on purpose (see `background` above baked into the
            // view tree) — GIF's transparency is 1-bit and movie codecs
            // typically have no alpha channel at all, so partial-alpha
            // edges would look wrong either way. `isOpaque` here just
            // tells ImageRenderer it doesn't need to preserve an alpha
            // channel it wouldn't get a good result from regardless.
            renderer.isOpaque = true
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
        let outerDiameter = canvasDiameter
        let ringDiameter = outerDiameter * (podDiameter / podFrameDiameter)
        let background: Color = colorScheme == .dark ? .black : .white

        var frames: [CGImage] = []
        frames.reserveCapacity(frameCount)

        for index in 0..<frameCount {
            let elapsed = Double(index) / fps
            guard
                let resolved = source.resolve(at: elapsed),
                let config = configs[resolved.segment.id]
            else { continue }

            let frameView = ZStack {
                background
                RingView(config: config, diameter: ringDiameter, overrideElapsed: resolved.phaseTime)
                    .frame(width: outerDiameter, height: outerDiameter)
                    // Composited against the opaque background above, so a
                    // fade reads as "dissolving into the backdrop" rather
                    // than producing partial alpha that GIF's 1-bit
                    // transparency and most movie codecs can't carry.
                    .opacity(resolved.opacity)
            }
            .frame(width: outerDiameter, height: outerDiameter)
            .environment(\.colorScheme, colorScheme)

            let renderer = ImageRenderer(content: frameView)
            renderer.scale = renderScale
            renderer.isOpaque = true
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

    public static func writeMovie(frames: [CGImage], to url: URL) async throws {
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

        let outputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = false

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
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

                    guard let pixelBuffer = pixelBuffer(from: frames[frameIndex], width: width, height: height) else {
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

    nonisolated private static func pixelBuffer(from cgImage: CGImage, width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBufferOut: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, attributes as CFDictionary, &pixelBufferOut)
        guard status == kCVReturnSuccess, let pixelBuffer = pixelBufferOut else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelBuffer
    }
}
