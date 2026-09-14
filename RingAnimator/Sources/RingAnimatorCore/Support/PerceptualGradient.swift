import SwiftUI

/// A perceptually smooth angular sweep through a set of colours.
///
/// **Why not the native one.** Apple added `Gradient.ColorSpace.perceptual`
/// (iOS 17) and it interpolates in OKLab — exactly this. But it is only
/// reachable via `Gradient.colorSpace(_:)`, which returns `AnyGradient`,
/// and no `AngularGradient` initializer takes an `AnyGradient` or a colour
/// space — checked against the macOS 27 SDK's swiftinterface, not assumed.
/// `AnyGradient` paints linearly. So the native path stops one shape short
/// of the ring, and this does the same math on angular stops.
///
/// `AngularGradient(colors:)` places each colour at an evenly spaced angle
/// and interpolates between them in sRGB. That has two visible costs on a
/// rotating ring. Each stop is a corner in the colour function — a spoke
/// the eye locks onto as it goes round — which is what made the wave ring
/// read as "a gradient rendered once, then spun" (Chris, 2026-09-14). And
/// sRGB is not perceptually uniform, so the midpoint between two vivid
/// colours is dull: cyan to violet passes through grey.
///
/// The fix is not re-rendering per frame — for a closed angular gradient,
/// rotating the view and shifting the stops are the same picture. The fix
/// is the stops: many of them, computed in OKLab, so the sweep has no
/// corners and the midpoints stay as saturated as the endpoints.
///
/// OKLab (Björn Ottosson, 2020) rather than OKLCH: interpolating in LCH
/// gives even more vivid through-hue paths but needs a hue-wrap policy,
/// and a wrong one puts a rainbow between two similar blues. Lab is the
/// safe, clearly-better-than-sRGB choice.
public enum PerceptualGradient {

    /// `count` colours sweeping through `colors` and back to the first, so
    /// the loop closes with no seam — the same reason the sparse version
    /// appended `colors[0]`.
    public static func closedSweep(through colors: [RGB], count: Int = 64) -> [Color] {
        guard let first = colors.first else { return [] }
        guard colors.count > 1 else { return Array(repeating: first.color, count: 2) }
        let loop = colors.map(OKLab.init) + [OKLab(first)]
        let segments = Double(loop.count - 1)
        return (0...count).map { i in
            let t = Double(i) / Double(count) * segments
            let index = min(Int(t), loop.count - 2)
            let f = t - Double(index)
            // Smoothstep within each segment, so the slope is zero at every
            // stop. Linear interpolation — in *any* colour space — leaves a
            // corner at each configured colour, because a closed sweep
            // through two colours goes A→B→A and reverses direction there.
            // That corner is the spoke; OKLab softens it, this removes it.
            let eased = f * f * (3 - 2 * f)
            return loop[index].mixed(with: loop[index + 1], t: eased).rgb.color
        }
    }

    /// `Color` → `RGB` costs an `NSColor` round trip (see `RGB`'s doc
    /// comment). The sweep is rebuilt every frame but only ever from the
    /// same handful of configured colours, so remember them.
    ///
    /// `@MainActor` because that is where every render that asks for it
    /// runs, and it makes the mutable cache concurrency-safe without a
    /// lock on the hot path.
    @MainActor private static var cache: [Color: RGB] = [:]

    @MainActor public static func rgb(_ color: Color) -> RGB {
        if let hit = cache[color] { return hit }
        let made = RGB(color)
        if cache.count > 64 { cache.removeAll() }
        cache[color] = made
        return made
    }
}

/// OKLab, with the sRGB transfer function on both ends.
struct OKLab {
    var L: Double
    var a: Double
    var b: Double

    init(L: Double, a: Double, b: Double) { self.L = L; self.a = a; self.b = b }

    init(_ c: RGB) {
        let r = Self.linear(c.red), g = Self.linear(c.green), bl = Self.linear(c.blue)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * bl)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * bl)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * bl)
        L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    }

    var rgb: RGB {
        let l_ = L + 0.3963377774 * a + 0.2158037573 * b
        let m_ = L - 0.1055613458 * a - 0.0638541728 * b
        let s_ = L - 0.0894841775 * a - 1.2914855480 * b
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        let r =  4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let bl = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        return RGB(red: Self.gamma(r), green: Self.gamma(g), blue: Self.gamma(bl))
    }

    func mixed(with other: OKLab, t: Double) -> OKLab {
        OKLab(L: L + (other.L - L) * t, a: a + (other.a - a) * t, b: b + (other.b - b) * t)
    }

    private static func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static func gamma(_ c: Double) -> Double {
        let v = min(max(c, 0), 1)
        return v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
    }
}
