import SwiftUI

/// Diode Mode, for the SwiftUI export.
///
/// The app's headline hardware-accurate mode used to export as the
/// *continuous* form of whatever animation was selected — a sweeping
/// gradient where the preview showed twenty fixed pixels — and `ExportView`
/// carried an on-screen notice saying so. This is the missing half.
///
/// It follows `RingView.diodeIntensity` exactly: each animation restated as
/// a scalar field over ring position, which is the form the hardware needs
/// anyway. Ported by hand rather than shared, because the generators emit
/// *strings* and a drop-in file can't import `RingAnimatorCore` — so the
/// two copies have to be kept honest by reading them side by side. Every
/// combination is compiled by `ExportCheck` (every type crossed with every
/// diode shape), which catches a body that doesn't build but not one that
/// computes the wrong number.
///
/// `voiceLevel` is 0 throughout. The app's field takes live mic level as an
/// input; an exported drop-in has no microphone, and inventing one would be
/// worse than leaving the term out.
extension CodeGenerators {

    /// The body that replaces `animationBody` when Diode Mode is on.
    static func swiftDiodeBody() -> String {
        """
        diodeRing(phase: phase, elapsed: elapsed)
        """
    }

    /// The per-type field, plus whatever helpers that type needs.
    static func swiftDiodeSupport(config: RingConfig) -> String {
        let type = config.animationType
        var out = """


            // MARK: - Diode Mode
            //
            // Every animation restated as a scalar field over ring position:
            // the pixels are soldered in place and an "animation" is a
            // brightness pattern swept across them. Mirrors
            // `RingView.diodeIntensity` in the design tool.

            private func diodeState(
                index i: Int,
                phase: Double,
                elapsed: Double,
                colors all: [Color]
            ) -> (color: Color, brightness: Double) {
                let count = max(diodeCount, 2)
                let position = Double(i) / Double(count)
                let head = phase / (2 * Double.pi)
                let ownColor = all[i % all.count]
                let floorBrightness = 0.06

        \(indent(swiftDiodeField(type), by: 8))
            }

        \(swiftDiodeRing(config: config))
        """

        if type == .ripple { out += "\n" + swiftRippleSupport() }
        if type == .bloom { out += "\n" + swiftBloomSupport() }
        return out
    }

    // MARK: - The field, per animation type

    private static func swiftDiodeField(_ type: RingAnimationType) -> String {
        switch type {
        case .wave:
            return """
            // A single crest travelling around fixed, individually-colored
            // pixels — the hardware reading of a sweeping gradient.
            let offset = (position - head).truncatingRemainder(dividingBy: 1)
            let crest = (cos(offset * 2 * Double.pi) + 1) / 2
            return (ownColor, max(crest, floorBrightness))
            """

        case .chasing:
            return """
            let lit = brightestComet(at: position, head: head, tail: max(trailFraction, 0.02), colorCount: 1)
            return (all[0], max(lit.brightness, floorBrightness))
            """

        case .dualChase:
            return """
            let tail = max(trailFraction, 0.02)
            let forward = brightestComet(at: position, head: head, tail: tail, colorCount: 1)
            let backward = brightestComet(at: position, head: -head, tail: tail, colorCount: 1)
            let secondary = all.count > 1 ? all[1] : all[0]
            return forward.brightness >= backward.brightness
                ? (all[0], max(forward.brightness, floorBrightness))
                : (secondary, max(backward.brightness, floorBrightness))
            """

        case .multiChase:
            return """
            let lit = brightestComet(at: position, head: head, tail: max(trailFraction, 0.02), colorCount: all.count)
            return (all[lit.index % all.count], lit.brightness)
            """

        case .alternating:
            return """
            let blink = (sin(phase) + 1) / 2
            return (ownColor, i.isMultiple(of: 2) ? blink : 1 - blink)
            """

        case .pulse:
            return """
            let breath = (sin(phase) + 1) / 2
            return (ownColor, min(0.25 + 0.75 * breath, 1))
            """

        case .ripple:
            return """
            // Drops landing at seeded positions and expanding symmetrically,
            // overlapping and accumulating — see `rippleLevel`.
            let level = min(rippleLevel(at: position, elapsed: elapsed) / rippleNormalization(), 1)
            return (ownColor, max(level, floorBrightness))
            """

        case .wobble:
            return """
            // The undulating radius becomes an undulating brightness — a
            // standing wave of three lobes, drifting with the phase.
            let lobes = 3.0
            let value = (sin(position * lobes * 2 * Double.pi + phase) + 1) / 2
            return (ownColor, 0.35 + 0.65 * value)
            """

        case .equalizer:
            return """
            // Each diode gets its own seeded, independent pulse.
            let seed = pseudoRandom(i)
            let localPhase = elapsed * speed * 2 * Double.pi * (0.6 + seed * 0.8) + seed * 2 * Double.pi
            let value = min((sin(localPhase) + 1) / 2, 1)
            return (ownColor, 0.15 + value * 0.85)
            """

        case .sparkle:
            return """
            let seed = pseudoRandom(i)
            let cycles = elapsed * speed * (0.5 + seed) + seed * 4
            let f = cycles - cycles.rounded(.down)
            let brightness = max(0, 1 - f * 4)
            return (ownColor, min(0.15 + brightness * 0.85, 1))
            """

        case .aurora:
            return """
            // Three soft bands drifting at their own rates; a diode takes
            // whichever band covers it most strongly.
            var best = (color: all[0], brightness: floorBrightness)
            for band in 0..<3 {
                let seed = pseudoRandom(band)
                let bandSpeed = speed * (0.12 + seed * 0.22)
                let bandPhase = (elapsed * bandSpeed + seed).truncatingRemainder(dividingBy: 1)
                let bandLength = 0.22 + seed * 0.16
                var within = (position - bandPhase).truncatingRemainder(dividingBy: 1)
                if within < 0 { within += 1 }
                guard within < bandLength else { continue }
                // Soft falloff toward each edge rather than a hard cut, to
                // match the blurred stroke the continuous version draws.
                let edge = sin((within / bandLength) * Double.pi)
                let pulse = 0.5 + 0.5 * sin(elapsed * (0.3 + seed * 0.4) + seed * 6)
                let brightness = min(edge * (0.35 + 0.5 * pulse), 1)
                if brightness > best.brightness {
                    best = (all[band % all.count], brightness)
                }
            }
            return best
            """

        case .bloom:
            return """
            // The lit floor, matching what the continuous version draws
            // underneath: this diode's share of the gradient, at `bloomBase`.
            let band = Int(position * Double(all.count)) % all.count
            let base = min(max(bloomBase, 0), 1)
            var best = (color: all[band], brightness: base)

            // Strongest patch covering this diode wins, with a cosine
            // falloff from its center so a patch's edges fade rather than
            // cutting off. Added to the floor, matching `.plusLighter`.
            for bloom in blooms(elapsed: elapsed, colorCount: all.count) {
                var offset = (position - bloom.center).truncatingRemainder(dividingBy: 1)
                if offset < -0.5 { offset += 1 }
                if offset > 0.5 { offset -= 1 }
                let half = bloom.length / 2
                guard abs(offset) < half, half > 0 else { continue }
                let falloff = (cos(offset / half * Double.pi) + 1) / 2
                let brightness = min(base + falloff * bloom.intensity, 1)
                if brightness > best.brightness {
                    best = (all[bloom.colorIndex % all.count], brightness)
                }
            }
            return best
            """

        case .liquidFill:
            return """
            // Diodes below the surface are lit, the one at the surface
            // brighter — a level gauge, which is what this already is.
            let riseCycles = elapsed * speed * 0.35
            let levelBase = (sin(riseCycles * 2 * Double.pi) + 1) / 2
            let slosh = sin(elapsed * speed * 2 * Double.pi * 1.8) * 0.04
            let level = min(max(levelBase + slosh, 0.02), 0.98)
            guard position <= level else { return (all[0], floorBrightness) }
            let isSurface = position > level - (1.0 / Double(count))
            let surfaceColor = all.count > 1 ? all[1] : all[0]
            return isSurface ? (surfaceColor, 1) : (all[0], 0.85)
            """
        }
    }

    // MARK: - Drawing

    /// One `Canvas` rather than a stack of positioned shapes — the same
    /// change that took the design tool's own ring from 1.03 ms a frame to
    /// 0.24. Specialized to the configured `diodeShape` here, since the
    /// generator knows which one it is and a drop-in file is easier to read
    /// without a runtime switch it will never take.
    private static func swiftDiodeRing(config: RingConfig) -> String {
        let drawing: String
        switch config.diodeShape {
        case .round:
            drawing = """
            context.fill(
                Path(ellipseIn: CGRect(
                    x: point.x - side / 2, y: point.y - side / 2,
                    width: side, height: side
                )),
                with: shading
            )
            """
        case .square, .bar:
            let aspect = config.diodeShape.aspect
            drawing = """
            // Rotated to sit tangent to the ring, so these read as
            // components mounted on a circular board.
            let width = side * \(aspect)
            let rect = CGRect(x: -width / 2, y: -side / 2, width: width, height: side)
            \(config.diodeShape == .bar
                ? "let shape = Path(roundedRect: rect, cornerRadius: side * 0.28)"
                : "let shape = Path(rect)")
            var transform = CGAffineTransform(translationX: point.x, y: point.y)
            transform = transform.rotated(by: angle + .pi / 2)
            context.fill(shape.applying(transform), with: shading)
            """
        case .segment:
            drawing = """
            // A wedge of the donut: `1 / count` of the circle minus the
            // gap, stroked to the band's full thickness with butt caps so
            // neighbours read as distinct segments.
            let slice = 1.0 / Double(count)
            let filled = slice * (1 - min(max(diodeGap, 0), 0.9))
            let start = Double(i) * slice + (slice - filled) / 2
            var wedge = Path()
            wedge.addArc(
                center: center,
                radius: radius,
                startAngle: .degrees(start * 360 - 90),
                endAngle: .degrees((start + filled) * 360 - 90),
                clockwise: false
            )
            context.stroke(wedge, with: shading, style: StrokeStyle(lineWidth: band, lineCap: .butt))
            """
        }

        return """
            private func diodeRing(phase: Double, elapsed: Double) -> some View {
                let all = activeColors(elapsed: elapsed)
                let count = max(diodeCount, 2)
                return Canvas { context, size in
                    let band = lineWidth
                    let radius = min(size.width, size.height) / 2 - band / 2
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let side = band * max(diodeScale, 0.1)

                    for i in 0..<count {
                        let lit = diodeState(index: i, phase: phase, elapsed: elapsed, colors: all)
                        // Floor lifts and compresses rather than clipping, so
                        // the low end keeps its shape.
                        let floor = min(max(diodeFloor, 0), 1)
                        let level = floor + (1 - floor) * lit.brightness
                        guard level > 0.001 else { continue }
                        let shading = GraphicsContext.Shading.color(lit.color.opacity(level))
                        let angle = (Double(i) / Double(count)) * 2 * Double.pi - .pi / 2
                        let point = CGPoint(
                            x: center.x + cos(angle) * radius,
                            y: center.y + sin(angle) * radius
                        )
        \(indent(drawing, by: 16))
                    }
                }
            }
        """
    }

    // MARK: - Type-specific helpers

    private static func swiftRippleSupport() -> String {
        """

            private struct Drop {
                var landedAt: Double
                var center: Double
            }

            private func drops() -> [Drop] {
                let count = max(Int(rippleDropCount.rounded()), 1)
                let loop = max(loopSeconds, 0.1)
                let seed = Int(rippleSeed.rounded())
                return (0..<count).map { i in
                    Drop(
                        landedAt: pseudoRandom(seed, i) * loop,
                        center: pseudoRandom(seed, i + 5000)
                    )
                }
            }

            /// Accumulated ripple brightness at a point on the ring.
            ///
            /// Contributions **sum** rather than taking the brightest: two
            /// fronts crossing should reinforce. Every drop is evaluated one
            /// loop earlier and one later so a drop landing near the end of
            /// the loop isn't cut off when the pattern repeats.
            private func rippleLevel(at position: Double, elapsed: Double) -> Double {
                let loop = max(loopSeconds, 0.1)
                let life = max(rippleLife, 0.05)
                let width = max(trailFraction, 0.01)
                let t = elapsed.truncatingRemainder(dividingBy: loop)
                var total = 0.0

                for drop in drops() {
                    for offset in [0.0, -loop, loop] {
                        let age = t - (drop.landedAt + offset)
                        guard age >= 0, age <= life else { continue }
                        let front = age * speed
                        var apart = abs(position - drop.center).truncatingRemainder(dividingBy: 1)
                        if apart > 0.5 { apart = 1 - apart }
                        let offsetFromFront = (apart - front) / width
                        let pulse = exp(-0.5 * offsetFromFront * offsetFromFront)
                        total += pulse * exp(-rippleDecay * age)
                    }
                }
                return total
            }

            /// Peak of `rippleLevel` over one loop, used to normalize —
            /// without it brightness scales with however many drops happen
            /// to overlap. Sampled rather than solved, and depends only on
            /// the parameters above, so it's computed once.
            private func rippleNormalization() -> Double {
                if let cached = Self.cachedRippleNormalization { return cached }
                let loop = max(loopSeconds, 0.1)
                var peak = 0.0001
                for step in 0..<32 {
                    let t = loop * Double(step) / 32
                    for p in 0..<16 {
                        peak = max(peak, rippleLevel(at: Double(p) / 16, elapsed: t))
                    }
                }
                Self.cachedRippleNormalization = peak
                return peak
            }

            nonisolated(unsafe) private static var cachedRippleNormalization: Double?
        """
    }

    private static func swiftBloomSupport() -> String {
        """

            private struct Bloom {
                var center: Double
                var length: Double
                var colorIndex: Int
                var intensity: Double
            }

            /// Patches that surface and sink back, each with its own period
            /// so they never fall into step, and rerolled per surfacing —
            /// where it comes up, how far, which way it drifts, what color.
            private func blooms(elapsed: Double, colorCount: Int) -> [Bloom] {
                let count = max(Int(bloomCount.rounded()), 2)
                let base = max(trailFraction, 0.02)
                let colors = max(colorCount, 1)

                return (0..<count).map { i in
                    let rateSeed = pseudoRandom(i + 211)
                    let period = max(6.0 / max(speed, 0.05) * (0.55 + rateSeed), 0.3)
                    let local = elapsed / period
                    let cycle = Int(local.rounded(.down))
                    let f = local - Double(cycle)

                    let placeSeed = pseudoRandom(i, cycle)
                    let peakSeed = pseudoRandom(i, cycle + 4096)
                    let driftSeed = pseudoRandom(i, cycle + 8192)
                    let colorSeed = pseudoRandom(i, cycle + 16384)

                    // 0 -> 1 -> 0 across the cycle: the whole shape of
                    // surfacing and sinking back, so a patch genuinely
                    // shrinks into nothing rather than fading at full size.
                    let envelope = sin(f * Double.pi)
                    let peak = 0.33 + peakSeed * 0.67
                    let length = base * peak * envelope
                    let drift = (driftSeed - 0.5) * 0.15 * f

                    return Bloom(
                        center: placeSeed + drift,
                        length: length,
                        colorIndex: Int(colorSeed * Double(colors)) % colors,
                        intensity: pow(envelope, 1.4) * (0.55 + peakSeed * 0.45)
                    )
                }
            }
        """
    }
}
