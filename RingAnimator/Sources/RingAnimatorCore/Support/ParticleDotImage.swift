import CoreGraphics

/// `CAEmitterCell` has no built-in vector shape — every cell needs a bitmap
/// in its `contents`, which it then tints via `.color` (treating the image
/// as a white-on-transparent mask). This builds that mask once: a small,
/// soft-edged white circle with a radial falloff, rendered directly via
/// Core Graphics so it works identically on iOS and macOS without needing
/// `UIGraphicsImageRenderer`/`NSImage` platform APIs.
enum ParticleDotImage {
    /// Cached after first render — every particle style/color reuses the
    /// same mask, only `CAEmitterCell.color` changes per cell.
    static let cgImage: CGImage = render()

    private static func render(diameter: CGFloat = 64) -> CGImage {
        let size = Int(diameter)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            // Extremely unlikely (only fails on invalid parameters above),
            // but CGImage can't be nil going forward, so fall back to a
            // 1x1 transparent pixel rather than force-unwrapping.
            return fallbackPixel()
        }

        let rect = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        let center = CGPoint(x: diameter / 2, y: diameter / 2)
        let radius = diameter / 2

        let gradientColors = [
            CGColor(red: 1, green: 1, blue: 1, alpha: 1),
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.6),
            CGColor(red: 1, green: 1, blue: 1, alpha: 0)
        ] as CFArray
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: [0, 0.5, 1]) else {
            return fallbackPixel()
        }

        context.clear(rect)
        context.drawRadialGradient(
            gradient,
            startCenter: center, startRadius: 0,
            endCenter: center, endRadius: radius,
            options: []
        )

        return context.makeImage() ?? fallbackPixel()
    }

    private static func fallbackPixel() -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        return context.makeImage()!
    }
}
