import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

extension Color {
    /// Builds a `Color` from a hex string like "#FF3B30" or "FF3B30".
    /// Falls back to white if the string can't be parsed.
    public init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r = Double((value & 0xFF0000) >> 16) / 255.0
        let g = Double((value & 0x00FF00) >> 8) / 255.0
        let b = Double(value & 0x0000FF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }

    /// Red/green/blue in 0...1.
    ///
    /// Same platform split `hexString` below already needed — SwiftUI's
    /// `Color` doesn't expose components directly, so it goes through
    /// `NSColor`/`UIColor`. Pulled out separately because interpolating
    /// between two colors needs the numbers, not a formatted string.
    public var rgbComponents: (red: Double, green: Double, blue: Double) {
        #if canImport(AppKit)
        let c = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor(self)
        return (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
        #elseif canImport(UIKit)
        let c = UIColor(self)
        var rf: CGFloat = 0, gf: CGFloat = 0, bf: CGFloat = 0, af: CGFloat = 0
        c.getRed(&rf, green: &gf, blue: &bf, alpha: &af)
        return (Double(rf), Double(gf), Double(bf))
        #else
        return (1, 1, 1)
        #endif
    }

    /// Hex string (e.g. "#4C9EFF") used both for on-screen labels and code export.
    public var hexString: String {
        #if canImport(AppKit)
        let c = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor(self)
        let r = Int(round(c.redComponent * 255))
        let g = Int(round(c.greenComponent * 255))
        let b = Int(round(c.blueComponent * 255))
        #elseif canImport(UIKit)
        let c = UIColor(self)
        var rf: CGFloat = 0, gf: CGFloat = 0, bf: CGFloat = 0, af: CGFloat = 0
        c.getRed(&rf, green: &gf, blue: &bf, alpha: &af)
        let r = Int(round(rf * 255))
        let g = Int(round(gf * 255))
        let b = Int(round(bf * 255))
        #endif
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
