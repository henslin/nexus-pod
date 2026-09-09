import Foundation
import AVFoundation
import VideoToolbox
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

/// Writes frames to a GIF and/or a movie **one at a time**, so an export
/// never holds more than the frame it's working on.
///
/// The exporter used to render every frame into an array and hand the
/// finished array to an encoder. That was fine for a 960×960 ring, and
/// stopped being fine the moment a frame could be a framed phone: 852×1796
/// is 6.1MB a frame, so a few seconds of animation is over a gigabyte of
/// `CGImage` sitting in memory waiting for an encoder that was always
/// going to consume it in order anyway.
///
/// Both encoders were already incremental underneath — `CGImageDestination`
/// takes images one at a time, and `AVAssetWriter` is a streaming API — so
/// this is mostly a matter of not getting in their way.
@MainActor
public final class ExportSink {

    public enum SinkError: Error, LocalizedError {
        case gifSetupFailed
        case gifFinalizeFailed
        case movieSetupFailed
        case pixelBufferCreationFailed
        case movieWritingFailed(String)

        public var errorDescription: String? {
            switch self {
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

    private let fps: Double
    private let transparent: Bool
    private let gifDither: Bool

    private var gifDestination: CGImageDestination?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var frameIndex = 0

    /// `size` is in pixels and has to be known up front — `AVAssetWriter`
    /// fixes its dimensions when the session starts, long before the last
    /// frame exists. Every canvas has a size that's known before rendering
    /// begins (`AnimationExporter.canvasSize`), so this costs nothing.
    public init(
        gif gifURL: URL?,
        movie movieURL: URL?,
        size: CGSize,
        fps: Double,
        transparent: Bool,
        frameCount: Int,
        gifDither: Bool = false
    ) throws {
        self.fps = fps
        self.transparent = transparent
        self.gifDither = gifDither

        if let gifURL {
            try? FileManager.default.removeItem(at: gifURL)
            guard let destination = CGImageDestinationCreateWithURL(
                gifURL as CFURL, UTType.gif.identifier as CFString, frameCount, nil
            ) else { throw SinkError.gifSetupFailed }
            CGImageDestinationSetProperties(destination, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
            ] as CFDictionary)
            gifDestination = destination
        }

        if let movieURL {
            try? FileManager.default.removeItem(at: movieURL)
            let width = Int(size.width), height = Int(size.height)
            guard let writer = try? AVAssetWriter(outputURL: movieURL, fileType: .mov) else {
                throw SinkError.movieSetupFailed
            }

            // H.264 has no alpha channel at all, so a transparent export is
            // written as HEVC with alpha instead — see `AnimationExporter`.
            var settings: [String: Any] = [
                AVVideoCodecKey: transparent ? AVVideoCodecType.hevcWithAlpha : AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height
            ]
            if transparent {
                settings[AVVideoCompressionPropertiesKey] = [
                    kVTCompressionPropertyKey_AlphaChannelMode as String:
                        kVTAlphaChannelMode_PremultipliedAlpha as String
                ]
            }

            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = false
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String:
                        transparent ? kCVPixelFormatType_32BGRA : kCVPixelFormatType_32ARGB,
                    kCVPixelBufferWidthKey as String: width,
                    kCVPixelBufferHeightKey as String: height
                ]
            )
            guard writer.canAdd(input) else { throw SinkError.movieSetupFailed }
            writer.add(input)
            writer.startWriting()
            writer.startSession(atSourceTime: .zero)

            self.writer = writer
            self.input = input
            self.adaptor = adaptor
        }
    }

    /// Frames must arrive in order — the presentation time is derived from
    /// how many have come before, not passed in.
    public func append(_ image: CGImage) async throws {
        if let gifDestination {
            // Only the GIF gets dithered. The movie is 8 bits per channel
            // with no palette in the way, so noise there would be noise for
            // nothing.
            var frame = gifDither ? (Self.dithered(image) ?? image) : image
            // Dither first, cutoff second: the dither only ever moves
            // colour, and the cutoff zeroes the colour of whatever it
            // clears — doing it the other way round would re-tint pixels
            // that had just been made invisible.
            if transparent { frame = Self.hardAlpha(frame) ?? frame }
            CGImageDestinationAddImage(gifDestination, frame, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]
            ] as CFDictionary)
        }

        if let input, let adaptor, let writer {
            // Non-real-time writers are almost always ready; when one isn't,
            // waiting is the whole of the back-pressure this needs.
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
                if writer.status == .failed {
                    throw SinkError.movieWritingFailed(writer.error?.localizedDescription ?? "unknown error")
                }
            }
            guard let buffer = Self.pixelBuffer(from: image, transparent: transparent) else {
                throw SinkError.pixelBufferCreationFailed
            }
            let time = CMTimeMultiply(CMTime(value: 1, timescale: CMTimeScale(fps)), multiplier: Int32(frameIndex))
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw SinkError.movieWritingFailed(writer.error?.localizedDescription ?? "append failed")
            }
        }
        frameIndex += 1
    }

    /// Perturbs each pixel by a fraction of a quantization step before the
    /// GIF encoder picks its palette.
    ///
    /// GIF is 8-bit indexed: 256 colours for the whole frame, of which a
    /// ring animation gets a hundred or so once the backdrop and glow have
    /// taken theirs. A smooth sweep through 2,900 colours has to land on
    /// those hundred, and it does so in flat steps — the bands.
    ///
    /// Ordered dithering breaks the steps up. Adding a small position-
    /// dependent offset *before* quantization makes neighbouring pixels in
    /// a flat band round to different palette entries, and the eye averages
    /// them back into the colour that wasn't available. Banding becomes
    /// fine noise, which reads as smoother even though strictly less of the
    /// original is preserved.
    ///
    /// Ordered rather than error-diffused (Floyd-Steinberg and friends) for
    /// one reason: this is animation. Error diffusion propagates each
    /// pixel's error to its neighbours, so a one-level change anywhere
    /// reshuffles the pattern downstream of it — which between consecutive
    /// frames is a crawling texture over the whole ring. A Bayer matrix is
    /// a pure function of (x, y), so the same colour at the same place
    /// dithers identically every frame and the noise sits still.
    ///
    /// **Alpha is deliberately untouched.** GIF alpha is 1-bit, so
    /// perturbing it wouldn't shade an edge, it would punch holes in one.
    ///
    /// Amplitude is one Bayer step either side of centre, scaled by
    /// `ditherStrength`. It costs file size — GIF's LZW compresses runs of
    /// identical pixels, which is exactly what this removes — so it's
    /// opt-in per export rather than always on.
    public static func dithered(_ image: CGImage, strength: Double = ditherStrength) -> CGImage? {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }

        // Core Graphics owns the buffer, deliberately.
        //
        // The obvious version allocates a `[UInt8]`, hands its
        // `baseAddress` to `CGContext(data:)` and returns the image — and
        // it is a use-after-free. `makeImage()` on a context with a
        // caller-supplied buffer wraps *that* memory rather than copying
        // it, so the CGImage outlives the array it points into. It appears
        // to work, which is the worst property a bug like this can have.
        // Passing `data: nil` makes CG allocate and manage the store for
        // the image's whole lifetime.
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let base = context.data else { return nil }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = context.bytesPerRow
        for y in 0..<height {
            let row = y * bytesPerRow
            for x in 0..<width {
                // -0.5 ... +0.5 from the matrix, scaled to levels.
                let cell = Double(bayer8[(y & 7) * 8 + (x & 7)]) / 64 - 0.5
                let offset = Int((cell * strength).rounded())
                guard offset != 0 else { continue }
                let index = row + x * 4
                // Alpha (the fourth byte) is skipped on purpose.
                for channel in 0..<3 {
                    let value = Int(bytes[index + channel]) + offset
                    bytes[index + channel] = UInt8(min(max(value, 0), 255))
                }
            }
        }
        return context.makeImage()
    }

    /// Calibrated by measurement, twice.
    ///
    /// The target isn't "no bands", it's "the same texture the render
    /// already had". Walking out through the glow, the source frame's runs
    /// of identical colour average 4.2 px; undithered, the GIF stretches
    /// them to 22.3 px, and those long flat plateaus are what the eye reads
    /// as banding.
    ///
    /// | strength | plateau run | pixel error | size |
    /// | --- | --- | --- | --- |
    /// | 0 | 22.3 px | 1.87 | 598 KB |
    /// | 1.0 | 8.5 px | 1.91 | 642 KB |
    /// | **1.5** | **3.0 px** | **2.26** | **976 KB** |
    /// | 2.0 | 2.7 px | 2.42 | 859 KB |
    ///
    /// 1.5 lands nearest the render's own 4.2. At 1.0 the plateaus are
    /// still twice the source's, so the bands survive; past 1.5 they go
    /// *finer* than the render, meaning the dither has stopped hiding
    /// bands and started being the texture.
    ///
    /// Re-derived once already. The first calibration said 2, and it was
    /// measured against a render whose halo was a flat default blue — the
    /// bug `RingView.emittedColor(of:fallback:)` fixes. Colouring the halo
    /// correctly put real gradients where there had been one flat wash,
    /// which changed what there was to quantize. Worth remembering that
    /// this constant is a property of the pictures, not of GIF.
    public static let ditherStrength: Double = 1.5

    /// Where "visible" starts, for a format with no in-between.
    ///
    /// 64 was still letting the glow through (the hole came back with the
    /// same 1,056 solid pixels as no cutoff at all); 96 cleared it; 128
    /// clears it with margin and keeps the ring at full width. Higher
    /// values were no cleaner and only risk eating a dim pattern.
    public static let transparentAlphaCutoff = 128

    /// The classic 8x8 ordered-dither threshold matrix.
    private static let bayer8: [Int] = [
         0, 32,  8, 40,  2, 34, 10, 42,
        48, 16, 56, 24, 50, 18, 58, 26,
        12, 44,  4, 36, 14, 46,  6, 38,
        60, 28, 52, 20, 62, 30, 54, 22,
         3, 35, 11, 43,  1, 33,  9, 41,
        51, 19, 59, 27, 49, 17, 57, 25,
        15, 47,  7, 39, 13, 45,  5, 37,
        63, 31, 55, 23, 61, 29, 53, 21
    ]

    /// Forces every pixel fully opaque or fully clear, and decides the
    /// cutoff itself rather than leaving it to the GIF encoder.
    ///
    /// GIF transparency is one bit: a pixel is either there or it isn't.
    /// The ring's glow is the opposite of that — a wide, soft wash of low
    /// alpha that fills the ring's own hole completely. Measured on the
    /// render, *every* pixel inside the hole carries partial alpha.
    ///
    /// Something has to decide where the line falls, and left alone the
    /// encoder decides per pixel as a side effect of choosing palette
    /// entries. The result is that patches of the glow snap to fully
    /// opaque while their neighbours vanish: a blotchy disc floating in the
    /// middle of a ring that should be empty. In one exported frame 10% of
    /// the hole came back solid.
    ///
    /// Choosing the cutoff here instead makes it uniform. At 128 the hole
    /// comes back completely clear while the ring itself is untouched —
    /// the band measured 4,858 opaque pixels against 4,603 before, since
    /// the stroke's own soft edge hardens outward to the cutoff contour
    /// rather than eroding.
    ///
    /// Applies to GIF only, and only when the export is transparent. The
    /// movie keeps real per-pixel alpha and needs none of this — which is
    /// still the better format for anything with a glow.
    public static func hardAlpha(_ image: CGImage, cutoff: Int = transparentAlphaCutoff) -> CGImage? {
        let width = image.width, height = image.height
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let base = context.data else { return nil }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let stride = context.bytesPerRow
        for y in 0..<height {
            for x in 0..<width {
                let i = y * stride + x * 4
                bytes[i + 3] = Int(bytes[i + 3]) >= cutoff ? 255 : 0
                if bytes[i + 3] == 0 { bytes[i] = 0; bytes[i + 1] = 0; bytes[i + 2] = 0 }
            }
        }
        return context.makeImage()
    }

    public func finish() async throws {
        if let gifDestination, !CGImageDestinationFinalize(gifDestination) {
            throw SinkError.gifFinalizeFailed
        }
        gifDestination = nil

        guard let writer, let input else { return }
        input.markAsFinished()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting { continuation.resume() }
        }
        if writer.status != .completed {
            throw SinkError.movieWritingFailed(writer.error?.localizedDescription ?? "unknown error")
        }
        self.writer = nil
        self.input = nil
    }

    nonisolated private static func pixelBuffer(from image: CGImage, transparent: Bool) -> CVPixelBuffer? {
        let width = image.width, height = image.height
        var out: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            transparent ? kCVPixelFormatType_32BGRA : kCVPixelFormatType_32ARGB,
            [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ] as CFDictionary,
            &out
        )
        guard status == kCVReturnSuccess, let buffer = out else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        // `noneSkipFirst` discards alpha, which is right for the opaque
        // path and would silently flatten the transparent one.
        let bitmapInfo = transparent
            ? CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            : CGImageAlphaInfo.noneSkipFirst.rawValue
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else { return nil }

        // Only matters when transparent: the buffer arrives with whatever
        // was in it, and an untouched pixel must be transparent.
        if transparent {
            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}
