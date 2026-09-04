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

    /// Which iPhone 17 Pro the screen sits in.
    ///
    /// These are Apple's own device frames from Apple Design Resources
    /// (the licence ships alongside the package), not a drawn
    /// approximation — the body used to be a rounded rectangle with a
    /// capsule for the Dynamic Island, which read as a phone at a glance
    /// and as a diagram in a deck.
    public enum DeviceFinish: String, CaseIterable, Identifiable, Sendable {
        case cosmicOrange = "Cosmic Orange"
        case deepBlue = "Deep Blue"
        case silver = "Silver"

        public var id: String { rawValue }

        var imageName: String {
            switch self {
            case .cosmicOrange: return "iphone-17-pro-cosmic-orange"
            case .deepBlue: return "iphone-17-pro-deep-blue"
            case .silver: return "iphone-17-pro-silver"
            }
        }

        public var image: Image {
            Image(imageName, bundle: .module)
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
            return device == nil ? phoneScreenSize : phoneFrameSize
        }
    }
    /// Matches `PhoneMockupView.screen`: the bar is inset 21pt on each
    /// side and sits 21pt off the bottom.
    private static let tabBarInset: CGFloat = 42
    private static let tabBarBottomPadding: CGFloat = 21
    /// The device frame artwork's own size, in points.
    ///
    /// Measured from the assets rather than assumed: the PNGs are
    /// 1350×2760 at 3x, and flood-filling the transparent interior gives
    /// an aperture of 1206×2622 inset 72/72/69/69 — that is, exactly
    /// `phoneScreenSize` at 3x, exactly centred. So the screen needs no
    /// scaling or offset, just a `ZStack` with the frame on top.
    public static let phoneFrameSize = CGSize(width: 450, height: 920)

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
                // The screen goes *behind* the frame: the artwork is opaque
                // everywhere outside its aperture, so it masks the screen's
                // square corners and supplies the Dynamic Island itself.
                ZStack {
                    background
                    screen
                    device.image
                        .resizable()
                        .frame(width: phoneFrameSize.width, height: phoneFrameSize.height)
                }
                .frame(width: phoneFrameSize.width, height: phoneFrameSize.height)
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
    /// flat array of `CGImage`s.
    ///
    /// Kept for `AlphaCheck`, which inspects pixels and so needs the frames
    /// themselves. Exporting goes through `export(...)` instead, which
    /// streams — holding 120 framed-phone frames costs 1.7GB against
    /// 281MB, measured.
    ///
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

    // MARK: - Writing
    //
    // Both encoders live in `ExportSink`, which takes frames one at a time.
    // These two just drive it.

    /// Renders and writes in one pass, never holding more than the frame
    /// being encoded — see `ExportSink` for why that matters now that a
    /// frame can be a framed phone rather than a small ring.
    public static func export(
        config: RingConfig,
        colorScheme: ColorScheme,
        loopCount: Int,
        transparent: Bool = false,
        canvas: Canvas = .ring,
        gif gifURL: URL? = nil,
        movie movieURL: URL? = nil,
        onProgress: @MainActor (Double) -> Void = { _ in }
    ) async throws {
        let export = exportConfig(from: config)
        let loopDuration = naturalLoopDuration(for: config)
        let frameCount = frameCount(duration: loopDuration, loopCount: loopCount)
        let sink = try makeSink(canvas: canvas, transparent: transparent, frameCount: frameCount, gif: gifURL, movie: movieURL)

        for index in 0..<frameCount {
            guard let image = render(
                canvas: canvas, config: export, elapsed: Double(index) / fps,
                opacity: 1, colorScheme: colorScheme, transparent: transparent
            ) else { continue }
            try await sink.append(image)
            onProgress(Double(index + 1) / Double(frameCount))
            await Task.yield()
        }
        try await sink.finish()
    }

    /// The timeline equivalent, frame for frame.
    public static func export(
        timeline: RingTimeline,
        colorScheme: ColorScheme,
        loopCount: Int,
        transparent: Bool = false,
        canvas: Canvas = .ring,
        gif gifURL: URL? = nil,
        movie movieURL: URL? = nil,
        onProgress: @MainActor (Double) -> Void = { _ in }
    ) async throws {
        guard !timeline.isEmpty, timeline.duration > 0 else { throw ExportError.noFrames }
        var source = timeline
        source.loops = true

        var configs: [UUID: RingConfig] = [:]
        for segment in timeline.segments where configs[segment.id] == nil {
            let config = RingConfig()
            segment.snapshot.apply(to: config)
            config.sequencePlaybackEnabled = false
            configs[segment.id] = exportConfig(from: config)
        }

        let frameCount = frameCount(duration: timeline.duration, loopCount: loopCount)
        let sink = try makeSink(canvas: canvas, transparent: transparent, frameCount: frameCount, gif: gifURL, movie: movieURL)

        for index in 0..<frameCount {
            guard
                let resolved = source.resolve(at: Double(index) / fps),
                let config = configs[resolved.segment.id],
                let image = render(
                    canvas: canvas, config: config, elapsed: resolved.phaseTime,
                    opacity: resolved.opacity, colorScheme: colorScheme, transparent: transparent
                )
            else { continue }
            try await sink.append(image)
            onProgress(Double(index + 1) / Double(frameCount))
            await Task.yield()
        }
        try await sink.finish()
    }

    /// Writes frames that already exist — the particle recorder's path,
    /// where the frames come from a real-time capture rather than a render.
    public static func write(
        frames: [CGImage],
        gif gifURL: URL? = nil,
        movie movieURL: URL? = nil,
        transparent: Bool = false
    ) async throws {
        guard let first = frames.first else { throw ExportError.noFrames }
        let sink = try ExportSink(
            gif: gifURL, movie: movieURL,
            size: CGSize(width: first.width, height: first.height),
            fps: fps, transparent: transparent, frameCount: frames.count
        )
        for frame in frames { try await sink.append(frame) }
        try await sink.finish()
    }

    private static func frameCount(duration: TimeInterval, loopCount: Int) -> Int {
        max(Int((duration * Double(max(loopCount, 1)) * fps).rounded()), 1)
    }

    private static func makeSink(
        canvas: Canvas, transparent: Bool, frameCount: Int, gif: URL?, movie: URL?
    ) throws -> ExportSink {
        let size = canvasSize(canvas)
        return try ExportSink(
            gif: gif, movie: movie,
            size: CGSize(width: size.width * renderScale, height: size.height * renderScale),
            fps: fps, transparent: transparent, frameCount: frameCount
        )
    }

    private static func render(
        canvas: Canvas, config: RingConfig, elapsed: Double, opacity: Double,
        colorScheme: ColorScheme, transparent: Bool
    ) -> CGImage? {
        let renderer = ImageRenderer(content: frameView(
            canvas: canvas, config: config, elapsed: elapsed, opacity: opacity,
            colorScheme: colorScheme, transparent: transparent
        ))
        renderer.scale = renderScale
        renderer.isOpaque = !transparent
        return renderer.cgImage
    }
}
