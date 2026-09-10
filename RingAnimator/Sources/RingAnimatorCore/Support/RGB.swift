import SwiftUI

/// A colour as three numbers, which is what everything in the render path
/// actually has and wants.
///
/// `Color` is the wrong currency for the inside of a frame. Recovering
/// components from one costs `NSColor(_:).usingColorSpace(.deviceRGB)` —
/// an object allocation and a colour-space conversion — and the render
/// path was paying it per diode, per sampled instant. Smoothing samples
/// the field at the playhead and at up to nine temporal taps, so a single
/// twenty-diode frame could ask for two hundred of them, and a sidebar of
/// twenty rows multiplied that again.
///
/// Measured by stubbing the conversion out entirely: it was **57% of a
/// smoothed stage frame** and 68% of the heaviest pattern's. Nothing else
/// in the render came close.
///
/// The waste was a round trip rather than the conversion itself. A stream
/// replay computes each LED's emitted light as three Doubles and wraps
/// them in a `Color`; the field then unwrapped them again a few
/// microseconds later. Carrying the numbers the whole way removes both
/// halves.
public struct RGB: Equatable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// The conversion, kept in one place so it's obvious where the cost is
    /// and easy to see that the render path doesn't pay it.
    public init(_ color: Color) {
        let c = color.rgbComponents
        self.init(red: c.red, green: c.green, blue: c.blue)
    }

    public var color: Color { Color(red: red, green: green, blue: blue) }

    public static let black = RGB(red: 0, green: 0, blue: 0)

    /// Straight linear interpolation, component-wise.
    public func mixed(with other: RGB, amount t: Double) -> RGB {
        RGB(red: red + (other.red - red) * t,
            green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t)
    }
}
