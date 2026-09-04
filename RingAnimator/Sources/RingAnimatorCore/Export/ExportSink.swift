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
        frameCount: Int
    ) throws {
        self.fps = fps
        self.transparent = transparent

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
            CGImageDestinationAddImage(gifDestination, image, [
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
