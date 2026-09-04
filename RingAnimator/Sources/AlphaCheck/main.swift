import Foundation
import SwiftUI
import AVFoundation
import AppKit
import RingAnimatorCore

// Proves a transparent export is actually transparent, end to end.
//
// This is the kind of feature that fails invisibly: a black backdrop baked
// into every frame looks perfectly correct in QuickTime and in the app's
// own preview, and only turns out to be wrong once someone drops the clip
// onto a light Figma frame and finds a black square around the ring. So
// rather than trust that `ImageRenderer.isOpaque = false` and
// `hevcWithAlpha` do what they say, this renders the real export path and
// counts pixels.
//
// `swift run AlphaCheck` — run by preflight.sh.

@MainActor
func run() async -> Int32 {
    var failed = false
    func check(_ label: String, _ ok: Bool, _ detail: String) {
        print("  \(ok ? "✓" : "✗") \(label) — \(detail)")
        if !ok { failed = true }
    }

    let config = RingConfig()
    config.animationType = .pulse
    config.speed = 1

    let frames = await AnimationExporter.renderFrames(
        config: config, colorScheme: .dark, loopCount: 1, transparent: true
    )
    guard let first = frames.first else {
        print("  ✗ rendered no frames")
        return 1
    }

    // 1. The rendered frames themselves carry alpha, the ring is still
    //    solid, and the backdrop is gone.
    //
    //    "Backdrop is gone" is deliberately not "the corners are fully
    //    clear": the ring's outer glow reaches the corners at roughly 4-10%
    //    alpha, which is correct — that haze is meant to composite over
    //    whatever it's dropped onto. What must not be there is an opaque
    //    black square, so the assertion is on how *little* alpha the
    //    corners carry, not on none at all.
    let (_, partial, _) = alphaHistogram(first)
    let corner = cornerAlpha(first)
    let peak = peakAlpha(first)
    check("frames have an alpha channel",
          first.alphaInfo != .none && first.alphaInfo != .noneSkipFirst && first.alphaInfo != .noneSkipLast,
          "alphaInfo \(first.alphaInfo.rawValue)")
    check("backdrop is gone", corner < 48, "corner alpha \(corner) of 255")
    check("the ring itself is still solid", peak > 180, "peak alpha \(peak) of 255")
    check("soft edges keep partial alpha", partial > 0, "\(partial) px partially transparent")

    // 2. The opaque path stays opaque — a regression that made *every*
    //    export transparent would be just as wrong.
    let opaqueFrames = await AnimationExporter.renderFrames(
        config: config, colorScheme: .dark, loopCount: 1, transparent: false
    )
    if let opaque = opaqueFrames.first {
        check("opaque export is still fully opaque", cornerAlpha(opaque) == 255,
              "corner alpha \(cornerAlpha(opaque)) of 255")
    }

    // 3. The movie file carries alpha through the encoder, which is the
    //    step most likely to silently flatten it.
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("alpha-check-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let movURL = dir.appendingPathComponent("clip.mov")
    do {
        try await AnimationExporter.write(frames: frames, movie: movURL, transparent: true)
    } catch {
        check("movie written", false, error.localizedDescription)
        return failed ? 1 : 0
    }

    let asset = AVURLAsset(url: movURL)
    if let track = try? await asset.loadTracks(withMediaType: .video).first,
       let desc = try? await track.load(.formatDescriptions).first {
        let ext = CMFormatDescriptionGetExtensions(desc) as? [String: Any] ?? [:]
        let carries = (ext["ContainsAlphaChannel"] as? NSNumber)?.boolValue ?? false
        check("movie declares an alpha channel", carries,
              "\(fourCC(CMFormatDescriptionGetMediaSubType(desc))), mode \(ext["AlphaChannelMode"] ?? "none")")
        check("decoded movie frame is transparent", decodedClearPixels(track: track) > 0,
              "clear px in first decoded frame")
    } else {
        check("movie has a video track", false, "no track")
    }

    // 4. GIF. Its transparency is 1-bit, so the assertion is only that the
    //    backdrop drops out — partial alpha is expected to be lost here.
    let gifURL = dir.appendingPathComponent("clip.gif")
    do {
        try await AnimationExporter.write(frames: frames, gif: gifURL)
        if let src = CGImageSourceCreateWithURL(gifURL as CFURL, nil),
           let img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            let (gifClear, _, gifTotal) = alphaHistogram(img)
            check("GIF backdrop drops out", Double(gifClear) / Double(gifTotal) > 0.4,
                  "\(gifClear) of \(gifTotal) px clear")
        }
    } catch {
        check("GIF written", false, error.localizedDescription)
    }

    // 5. The streaming path — what every export sheet actually calls now.
    //    Rendering and encoding run as one pass, so this is also the only
    //    check that a real file comes out the far end.
    let streamed = dir.appendingPathComponent("streamed")
    do {
        try await AnimationExporter.export(
            config: config, colorScheme: .dark, loopCount: 1, transparent: true,
            canvas: .appUI(tab: .dashboard, device: .blackTitanium),
            gif: streamed.appendingPathExtension("gif"),
            movie: streamed.appendingPathExtension("mov")
        )
        let gifSize = fileSize(streamed.appendingPathExtension("gif"))
        let movSize = fileSize(streamed.appendingPathExtension("mov"))
        check("streaming export writes a GIF", gifSize > 1024, "\(gifSize) bytes")
        check("streaming export writes a movie", movSize > 1024, "\(movSize) bytes")

        let framed = AVURLAsset(url: streamed.appendingPathExtension("mov"))
        if let track = try? await framed.loadTracks(withMediaType: .video).first {
            let size = try? await track.load(.naturalSize)
            let expected = AnimationExporter.canvasSize(.appUI(tab: .dashboard, device: .blackTitanium))
            let want = CGSize(width: expected.width * AnimationExporter.renderScale,
                              height: expected.height * AnimationExporter.renderScale)
            check("framed movie is the right size", size == want, "\(size.map { "\(Int($0.width))x\(Int($0.height))" } ?? "?") vs \(Int(want.width))x\(Int(want.height))")
        }
    } catch {
        check("streaming export", false, error.localizedDescription)
    }

    return failed ? 1 : 0
}

func fileSize(_ url: URL) -> Int {
    ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int) ?? 0
}

/// Redraws into a known layout rather than reading `CGImage` bytes
/// directly — the renderer's own format isn't guaranteed. Alpha lands in
/// byte 0 of each pixel (`premultipliedFirst`).
func alphaBuffer(_ image: CGImage) -> ([UInt8], Int, Int) {
    let w = image.width, h = image.height
    var buffer = [UInt8](repeating: 0, count: w * h * 4)
    buffer.withUnsafeMutableBytes { raw in
        guard let ctx = CGContext(
            data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return }
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return (buffer, w, h)
}

func alphaHistogram(_ image: CGImage) -> (clear: Int, partial: Int, total: Int) {
    let (buffer, w, h) = alphaBuffer(image)
    var clear = 0, partial = 0
    for p in stride(from: 0, to: w * h * 4, by: 4) {
        let a = buffer[p]
        if a == 0 { clear += 1 } else if a < 250 { partial += 1 }
    }
    return (clear, partial, w * h)
}

// Main-actor isolated so the track — which comes from a main-actor
// context above — never crosses an isolation boundary.
@MainActor
func decodedClearPixels(track: AVAssetTrack) -> Int {
    guard let asset = track.asset, let reader = try? AVAssetReader(asset: asset) else { return 0 }
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ])
    reader.add(output)
    reader.startReading()
    guard let sample = output.copyNextSampleBuffer(),
          let buffer = CMSampleBufferGetImageBuffer(sample) else { return 0 }
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else { return 0 }
    var clear = 0
    for y in 0..<h {
        for x in 0..<w where base[y * stride + x * 4 + 3] == 0 { clear += 1 }
    }
    return clear
}

/// The four corners, which is where a baked-in backdrop would show up.
func cornerAlpha(_ image: CGImage) -> Int {
    let (buffer, w, h) = alphaBuffer(image)
    let corners = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]
    return corners.map { Int(buffer[($0.1 * w + $0.0) * 4]) }.max() ?? 0
}

func peakAlpha(_ image: CGImage) -> Int {
    let (buffer, w, h) = alphaBuffer(image)
    var peak = 0
    for p in stride(from: 0, to: w * h * 4, by: 4) { peak = max(peak, Int(buffer[p])) }
    return peak
}

func fourCC(_ code: FourCharCode) -> String {
    let bytes = [UInt8((code >> 24) & 0xff), UInt8((code >> 16) & 0xff), UInt8((code >> 8) & 0xff), UInt8(code & 0xff)]
    return String(bytes: bytes, encoding: .ascii) ?? "????"
}

print("transparent export:")
let status = await run()
exit(status)
