import Foundation
import SwiftUI
import AppKit
import RingAnimatorCore

// The two colour-smoothness features, gated together: Blend, and the GIF
// dither.
//
// Proves Blend mixes colour and *only* colour.
//
// The whole promise of the control is a negative one: turn it up and the
// hues run together, while the ring's silhouette, its edges and its
// brightness stay exactly where they were. A pixel blur masked back to the
// band would satisfy the first half and quietly break the second — the ring
// would dim at its own edges — and it would look plausible in a screenshot
// either way. So this doesn't eyeball it. It renders the real export path
// twice, once at 0 and once at the top of the range, and compares the two
// images channel by channel.
//
// The load-bearing assertion is #2: the alpha channel must come back
// *byte-identical*. Alpha is where every edge in the picture lives, so if
// blending had touched geometry or brightness at all, it would show up
// there.
//
// `swift run BlendCheck` — run by preflight.sh.

@MainActor
func run() async -> Int32 {
    var failed = false
    var ran = 0
    func check(_ label: String, _ ok: Bool, _ detail: String) {
        ran += 1
        print("  \(ok ? "✓" : "✗") \(label) — \(detail)")
        if !ok { failed = true }
    }

    // `.wave` colours each diode from the palette by index, so with two
    // colours adjacent diodes are as different as the palette allows —
    // the hardest case for a blend to smooth and the easiest to measure.
    func makeConfig(blend: Double, monochrome: Bool = false) -> RingConfig {
        let config = RingConfig()
        config.animationType = .wave
        config.speed = 1
        // Smoothing is a Diode Mode treatment — it operates on the twenty
        // sampled levels, and there are no diodes to smooth without it.
        config.diodeModeEnabled = true
        // Pinned, not inherited. These measurements are about Blend, and a
        // check whose numbers move when a product default moves is
        // measuring the default as much as the feature.
        config.ringScale = 1
        config.smoothingEnabled = true
        config.smoothingGradientRing = true
        config.smoothingColorBlend = blend
        config.primaryColor = Color(red: 1, green: 0.1, blue: 0.1)
        config.secondaryColor = monochrome
            ? Color(red: 1, green: 0.1, blue: 0.1)
            : Color(red: 0.1, green: 0.3, blue: 1)
        return config
    }

    func firstFrame(_ config: RingConfig) async -> CGImage? {
        await AnimationExporter.renderFrames(
            config: config, colorScheme: .dark, loopCount: 1, transparent: true
        ).first
    }

    guard let flat = await firstFrame(makeConfig(blend: 0)),
          let blended = await firstFrame(makeConfig(blend: 4)) else {
        print("  ✗ rendered no frames")
        return 1
    }

    guard let a = Pixels(flat), let b = Pixels(blended), a.matches(b) else {
        print("  ✗ frames came back in mismatched formats")
        return 1
    }

    // 1. The control is wired to something.
    //
    //    Stated first and separately because it is the failure this project
    //    keeps hitting: a check that builds its own inputs proves the
    //    mechanism works while the app hands the mechanism nothing.
    let rgbDelta = a.meanColorDifference(b)
    check("Blend changes the render", rgbDelta > 2,
          String(format: "mean |ΔRGB| %.1f of 255", rgbDelta))

    // 2. Nothing but colour moved.
    //
    //    Alpha is where every edge in the picture lives, so this is the
    //    assertion that actually says "clean edges": if blending had
    //    softened the band, thinned it, or dimmed it, the silhouette would
    //    have moved and it would show up here.
    //
    //    Not quite bit-identical, and the tolerance is measured rather than
    //    guessed. Rewriting a gradient stop's colour changes what the
    //    rasterizer rounds when it premultiplies, so a handful of pixels
    //    land a single level either side: at the top of the range that was
    //    54 pixels out of 725,000 lit, none of them off by more than 1.
    //    Scattered ±1 rounding is a different shape of error from a blurred
    //    edge — that would be a continuous band of large differences
    //    following the ring — so the bound is on both magnitude and count.
    let (worst, differing, litCount) = a.alphaProfile(b)
    let strayFraction = Double(differing) / Double(max(litCount, 1))
    check("edges, silhouette and brightness are untouched",
          worst <= 1 && strayFraction < 0.0001,
          String(format: "max |Δalpha| %d, %d px of %d lit (%.4f%%)",
                 worst, differing, litCount, strayFraction * 100))

    // 3. The hues actually ran together, rather than merely changing.
    //
    //    Measured as the mean step between neighbouring samples taken
    //    around the band: that is precisely "how abrupt are the colour
    //    changes as you travel around the ring", which is what the eye
    //    reads as blending.
    let flatStep = a.meanAngularStep()
    let blendedStep = b.meanAngularStep()
    check("neighbouring colours converge", blendedStep < flatStep * 0.6,
          String(format: "angular step %.1f → %.1f", flatStep, blendedStep))

    // 4. A weighted average, not a smudge toward black.
    //
    //    One colour blended with itself has to be itself. If the kernel
    //    were pulling in unlit neighbours — the classic blur mistake this
    //    is written to avoid — a monochrome ring would come back darker.
    if let monoFlat = await firstFrame(makeConfig(blend: 0, monochrome: true)),
       let monoBlend = await firstFrame(makeConfig(blend: 4, monochrome: true)),
       let m0 = Pixels(monoFlat), let m1 = Pixels(monoBlend) {
        let monoDelta = m0.meanColorDifference(m1)
        check("a single-colour ring is unchanged by blending", monoDelta < 0.5,
              String(format: "mean |ΔRGB| %.2f of 255", monoDelta))
    }

    // 5. The setting survives a save and a load.
    let source = makeConfig(blend: 2.5)
    let restored = RingConfig()
    RingPreset(name: "blend", config: source).apply(to: restored)
    check("Blend round-trips through a preset", restored.smoothingColorBlend == 2.5,
          "\(restored.smoothingColorBlend)")

    // 6. Off by default, so importing the library doesn't restyle it.
    check("Blend is off by default", RingConfig().smoothingColorBlend == 0,
          "\(RingConfig().smoothingColorBlend)")

    // ---- The halo takes the ring's colour ----
    //
    // The glow was drawn in the palette's Primary. For anything authored
    // in this app that is also what's on the ring, so it looked right and
    // was never questioned — but an imported pattern carries its own RGB
    // per LED and has nothing to do with the palette, so every one of them
    // glowed the same default cyan-blue. Through Liquid Glass the halo is
    // most of what the material refracts, so a red pattern read as a red
    // ring sitting on a stale blue one.
    for name in ["arm_away", "arm_home"] where FirmwarePatternStream.stream(named: name) != nil {
        let streamed = RingConfig()
        streamed.diodeModeEnabled = true
        streamed.smoothingEnabled = true
        streamed.firmwarePatternStream = name
        streamed.glowEnabled = true
        guard let frame = await AnimationExporter.renderFrames(
            config: streamed, colorScheme: .dark, loopCount: 1, transparent: true
        ).dropFirst(12).first, let px = Pixels(frame) else { continue }

        let (band, halo) = px.bandAndHalo()
        // Hue agreement, not equality: the halo is the average over the
        // whole ring and much dimmer, so it can't match a single point on
        // the band exactly. What it must not do is disagree about which
        // channel dominates — red band, blue halo is the bug.
        let bandDominant = [band.0, band.1, band.2].firstIndex(of: max(band.0, band.1, band.2))
        let haloDominant = [halo.0, halo.1, halo.2].firstIndex(of: max(halo.0, halo.1, halo.2))
        check("\(name)'s halo agrees with its ring", bandDominant == haloDominant,
              "band rgb\(band), halo rgb\(halo)")
    }

    // ---- Ring Size shrinks the ring, not the canvas ----
    //
    // Two controls that sound alike and aren't: Preview Size moves the
    // camera, Ring Size changes the design. The way to tell them apart in
    // a rendered frame is that Ring Size must leave the frame's dimensions
    // alone while moving the band inward.
    do {
        func bandRadius(_ scale: Double) async -> (radius: Double, width: Int)? {
            let cfg = RingConfig()
            cfg.diodeModeEnabled = true
            cfg.smoothingEnabled = true
            cfg.animationType = .pulse
            cfg.glowEnabled = false
            cfg.ringScale = scale
            let rendered = await AnimationExporter.renderFrames(
                config: cfg, colorScheme: .dark, loopCount: 1, transparent: true
            )
            // Normalized rather than read directly: `ImageRenderer` hands
            // back a 16-bit, 64-bit-per-pixel wide-gamut image for some
            // configs and an 8-bit one for others, and `Pixels` reads
            // bytes. Redrawing into a known layout costs one blit and
            // makes the measurement independent of that choice.
            guard let frame = rendered.first, let px = Pixels.normalized(frame) else { return nil }
            let cx = px.width / 2, cy = px.height / 2
            var bandY = 0, best = 0
            for y in 0..<cy where px.alpha(x: cx, y: y) > best {
                best = px.alpha(x: cx, y: y); bandY = y
            }
            return (Double(cy - bandY) / Double(px.width), px.width)
        }

        if let full = await bandRadius(1), let small = await bandRadius(0.5) {
            check("Ring Size shrinks the ring",
                  small.radius < full.radius * 0.7,
                  String(format: "band at %.3f of the frame, was %.3f", small.radius, full.radius))
            check("and leaves the canvas alone", small.width == full.width,
                  "\(small.width) px wide either way")
        }

        let restored = RingConfig()
        let source = RingConfig()
        source.ringScale = 0.6
        RingPreset(name: "scale", config: source).apply(to: restored)
        check("Ring Size round-trips through a preset", restored.ringScale == 0.6,
              "\(restored.ringScale)")
        // Every preset written before Ring Size existed carries no value
        // for it, so this is also the assertion that the whole bundled
        // library adopts the default rather than sitting at the device's
        // 34pt.
        let untouched = RingPreset(name: "old", config: RingConfig())
        var stripped = untouched
        stripped.ringScale = nil
        let adopted = RingConfig()
        stripped.apply(to: adopted)
        check("a preset with no Ring Size adopts the default",
              adopted.ringDiameterPoints == RingConfig.defaultRingDiameterPoints,
              "\(adopted.ringDiameterPoints) pt")
    }

    // ---- Ring Size is the ring's outer diameter, in points ----
    //
    // The rule this holds the app to: the primary ring — the stroke, not
    // the light around it — is exactly as many points across as Ring Size
    // says. Effects are free to spill outside it or bleed inside it; they
    // just don't count toward the number. Blur and Scale Pulse deliberately
    // exceed it, which is why glow and blur are off here: the assertion is
    // about the ring, and anything that measures the halo is measuring
    // something the control was never claiming to describe.
    //
    // Stated in points rather than fractions of the canvas because points
    // are what the control says and what a fraction can quietly disagree
    // with. `AnimationExporter` draws the ring at the same 34/62 pod ratio
    // the app's preview uses, so the ring's nominal diameter on a canvas of
    // `canvasDiameter` points is `canvasDiameter * 34/62 * ringScale`.
    do {
        func outerDiameterPoints(diode: Bool, width: Double, scale: Double) async -> Double? {
            let cfg = RingConfig()
            cfg.animationType = .wave
            cfg.glowEnabled = false
            cfg.blurRadius = 0
            cfg.scalePulseEnabled = false
            cfg.diodeModeEnabled = diode
            cfg.smoothingEnabled = diode
            cfg.lineWidth = width
            cfg.ringScale = scale
            guard let frame = await AnimationExporter.renderFrames(
                config: cfg, colorScheme: .dark, loopCount: 1, transparent: true
            ).dropFirst(8).first, let px = Pixels.normalized(frame) else { return nil }
            let cx = px.width / 2, cy = px.height / 2
            for y in 0..<cy where px.alpha(x: cx, y: y) > 32 {
                // Radius in pixels -> diameter in canvas points.
                let radiusFraction = Double(cy - y) / Double(px.width)
                return radiusFraction * 2 * AnimationExporter.canvasDiameter
            }
            return nil
        }

        // The control now reads in device points, so state the invariant
        // the designer is actually relying on: the number on the slider is
        // the ring's diameter in a real tab bar, and the preview is that
        // same ring magnified rather than a different shape.
        let atRest = RingConfig()
        check("Ring Size reads 44pt at rest — the app's default",
              atRest.ringDiameterPoints == RingConfig.defaultRingDiameterPoints,
              "\(atRest.ringDiameterPoints) pt")
        let sized = RingConfig()
        sized.ringDiameterPoints = 24
        check("setting 24pt is 24/34 of the pod",
              abs(sized.ringScale - 24.0 / 34.0) < 0.0001,
              String(format: "ringScale %.4f", sized.ringScale))

        let podRatio = RingConfig.tabBarRingDiameter / RingConfig.tabBarPodDiameter
        for scale in [1.0, 0.5] {
            let expected = AnimationExporter.canvasDiameter * podRatio * scale
            for (label, diode) in [("Diode Mode", true), ("continuous", false)] {
                for width in [2.0, 16.0] {
                    guard let measured = await outerDiameterPoints(diode: diode, width: width, scale: scale)
                    else { continue }
                    // Two points of tolerance: the edge is antialiased and
                    // the scan lands on whole pixels.
                    check("\(label) at \(Int(scale * 100))% is \(Int(expected))pt across, width \(Int(width))",
                          abs(measured - expected) < 2,
                          String(format: "measured %.1f pt", measured))
                }
            }
        }
    }

    // ---- Nothing escapes the pod ----
    //
    // Ring Size runs well past the 62pt pod so a ring can animate up into
    // the crop, but the crop itself is absolute: the pod bounds everything,
    // ring, glow and particles alike. This asserts the containment rather
    // than the growth — an overflowing ring bled past the glass in one
    // surface and was contained in another, and which surface you happened
    // to be looking at decided what you saw.
    do {
        func appUIFrame(_ scale: Double) async -> Pixels? {
            let cfg = RingConfig()
            cfg.animationType = .wave
            cfg.glowEnabled = true
            cfg.ringScale = scale
            return await AnimationExporter.renderFrames(
                config: cfg, colorScheme: .dark, loopCount: 1, transparent: true,
                canvas: .appUI(tab: .dashboard, device: nil)
            ).dropFirst(8).first.flatMap(Pixels.normalized)
        }

        if let base = await appUIFrame(1), let big = await appUIFrame(5) {
            // How far up the screen the two renders differ. The app UI
            // behind the ring is identical either way, so any difference is
            // the ring — and it must all sit inside the tab bar.
            var highest = big.height
            for y in 0..<big.height {
                var changed = 0
                for x in Swift.stride(from: 0, to: big.width, by: 4) {
                    let a = big.color(x: x, y: y), b = base.color(x: x, y: y)
                    if abs(a.0 - b.0) + abs(a.1 - b.1) + abs(a.2 - b.2) > 60 { changed += 1 }
                }
                if changed > 3 { highest = y; break }
            }
            let reach = Double(big.height - highest) / Double(big.height)
            check("a 170pt ring stays inside the tab bar", reach < 0.12,
                  String(format: "differs only in the bottom %.0f%% of the screen", reach * 100))
        }
    }

    // ---- Ring Size means the same thing in both renderers ----
    //
    // Diode Mode and the continuous renderer draw the ring differently, and
    // for the life of the app they disagreed about how big "the ring" is:
    // the diode band's outer edge lands on `size`, while a SwiftUI stroke
    // is centred on its path, so the continuous ring hung half a line width
    // outside it. Two animations set to the same Ring Size came out visibly
    // different sizes, and the continuous one *grew* as you thickened it.
    do {
        func outerEdge(diode: Bool, width: Double) async -> Double? {
            let cfg = RingConfig()
            cfg.glowEnabled = false
            cfg.diodeModeEnabled = diode
            cfg.animationType = .wave
            cfg.lineWidth = width
            guard let frame = await AnimationExporter.renderFrames(
                config: cfg, colorScheme: .dark, loopCount: 1, transparent: true
            ).dropFirst(8).first, let px = Pixels.normalized(frame) else { return nil }
            let cx = px.width / 2, cy = px.height / 2
            for y in 0..<cy where px.alpha(x: cx, y: y) > 32 {
                return Double(cy - y) / Double(px.width)
            }
            return nil
        }

        for width in [6.0, 16.0] {
            if let diode = await outerEdge(diode: true, width: width),
               let smooth = await outerEdge(diode: false, width: width) {
                check("both renderers agree on ring size at width \(Int(width))",
                      abs(diode - smooth) < 0.006,
                      String(format: "diode %.3f vs continuous %.3f", diode, smooth))
            }
        }

        // And the ring stops growing when the stroke does. This is the half
        // that made it feel broken: Ring Width was silently a second size
        // control.
        if let thin = await outerEdge(diode: false, width: 2),
           let thick = await outerEdge(diode: false, width: 16) {
            check("Ring Width no longer changes the ring's size",
                  abs(thin - thick) < 0.006,
                  String(format: "%.3f at width 2, %.3f at width 16", thin, thick))
        }
    }

    // ---- A transparent GIF's hole stays a hole ----
    //
    // GIF alpha is one bit and the glow is a wide wash of low alpha that
    // fills the ring's own hole completely, so *something* has to decide
    // where "visible" starts. Left to the encoder it decides per pixel
    // while picking palette entries, and patches of glow snap solid: a
    // blotchy disc in the middle of a ring that should be empty.
    do {
        let streamed = RingConfig()
        streamed.diodeModeEnabled = true
        streamed.smoothingEnabled = true
        streamed.firmwarePatternStream = "listen_rainbow_twin_pulse"
        streamed.glowEnabled = true
        let frames = Array((await AnimationExporter.renderFrames(
            config: streamed, colorScheme: .dark, loopCount: 1, transparent: true
        )).dropFirst(30).prefix(4))

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hole-check-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // The render itself is the control: if the glow *didn't* fill the
        // hole there would be nothing here to fix, and this check would be
        // passing for the wrong reason.
        if let source = frames.first.flatMap(Pixels.init) {
            let sourceHole = source.holeAndBand()
            check("the glow really does fill the ring's hole", sourceHole.partialHole > 1000,
                  "\(sourceHole.partialHole) px of partial alpha inside the ring")
        }

        let url = dir.appendingPathComponent("hole.gif")
        try? await AnimationExporter.write(frames: frames, gif: url, transparent: true)
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
           let context = CGContext(
                data: nil, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            if let px = context.makeImage().flatMap(Pixels.init) {
                let stats = px.holeAndBand()
                check("no blob survives into the GIF", stats.hole == 0,
                      "\(stats.hole) opaque px inside the ring")
                check("and the ring itself is still there", stats.band > 3500,
                      "\(stats.band) opaque px on the band")
            }
        }
    }

    // ---- Rendering doesn't build the voice machinery ----
    //
    // `RingConfig` is the document, and it is also what every thumbnail
    // row, timeline step and cue preview keeps as a `@StateObject`. Its
    // initializer used to read the Keychain and build a voice service, a
    // conversation controller and a Combine bridge — 0.45ms each, and a
    // hundred live subscriptions behind a list of pictures. It is now
    // built on first use, and one careless `config.elevenLabs` on a draw
    // path would silently undo that.
    do {
        let rendering = RingConfig()
        rendering.diodeModeEnabled = true
        rendering.smoothingEnabled = true
        _ = await AnimationExporter.renderFrames(
            config: rendering, colorScheme: .dark, loopCount: 1, transparent: false
        ).first
        check("rendering a frame leaves the voice stack unbuilt",
              !rendering.hasBuiltVoiceStack,
              rendering.hasBuiltVoiceStack ? "something on the draw path reached for it" : "unbuilt")

        let asked = RingConfig()
        _ = asked.elevenLabs
        check("and asking for it still builds it", asked.hasBuiltVoiceStack,
              "\(asked.hasBuiltVoiceStack)")
    }

    // ---- Previews stop when nobody is looking ----
    //
    // Measured on the shipped build: a backgrounded window was costing
    // about a quarter of a core, continuously, drawing rings for nobody.
    // Freezing them takes it to zero.
    //
    // Driven by AppKit notifications, which is exactly the sort of wiring
    // that looks right and does nothing — the first version recorded the
    // app's launch state without applying it, so an app launched into the
    // background rendered at full rate until the next activation change
    // happened to arrive. Posting the notifications here tests the state
    // machine rather than the guess.
    do {
        let activity = RenderActivity.shared
        let center = NotificationCenter.default

        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        try? await Task.sleep(for: .milliseconds(60))
        check("previews run when the app is active", activity.isRendering, "\(activity.isRendering)")

        center.post(name: NSApplication.didResignActiveNotification, object: nil)
        try? await Task.sleep(for: .milliseconds(60))
        check("and stop when it goes to the background", !activity.isRendering, "\(activity.isRendering)")

        // The recorder captures the app's own window frame by frame, so a
        // click elsewhere mid-capture must not freeze what it is recording.
        activity.beginForcedRendering()
        check("a recording keeps them running anyway", activity.isRendering, "\(activity.isRendering)")
        activity.endForcedRendering()
        check("and they stop again when it finishes", !activity.isRendering, "\(activity.isRendering)")

        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        try? await Task.sleep(for: .milliseconds(60))
        check("coming back to the app resumes them", activity.isRendering, "\(activity.isRendering)")
    }

    // ---- The GIF dither ----
    //
    // Banding is a *contour*, not an error magnitude, and measuring it the
    // obvious way gets the wrong answer. Undithered, a GIF of a blended
    // ring is within 0.64 of 255 of the source on average — near-perfect by
    // any error metric — and visibly striped, because GIF's palette turns a
    // shallow gradient into wide flat plateaus and the eye reads the seams
    // between them. So this measures plateau *length*: walk outward through
    // the glow and record how far you travel before the colour changes.
    //
    // The target is the source render's own texture, not "no plateaus at
    // all" — overshooting means the dither has stopped hiding bands and
    // started adding noise of its own.
    let ditherConfig = makeConfig(blend: 3)
    ditherConfig.animationType = .multiChase
    ditherConfig.trailFraction = 0.9
    ditherConfig.additionalColors = [Color(red: 0.2, green: 1, blue: 0.3)]
    let ditherFrames = Array((await AnimationExporter.renderFrames(
        config: ditherConfig, colorScheme: .dark, loopCount: 1, transparent: false
    )).prefix(12))

    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("blend-check-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    guard let sourcePixels = ditherFrames.first.flatMap(Pixels.init) else {
        print("  ✗ rendered no frames for the dither pass")
        return 1
    }
    let sourceRun = sourcePixels.meanPlateauRun()

    func writeGIF(_ name: String, dithered: Bool) async -> (pixels: Pixels?, bytes: Int) {
        let url = dir.appendingPathComponent(name)
        let staged = dithered
            ? ditherFrames.compactMap { ExportSink.dithered($0) }
            : ditherFrames
        try? await AnimationExporter.write(frames: staged, gif: url)
        let bytes = ((try? Data(contentsOf: url))?.count) ?? 0
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let context = CGContext(
                data: nil, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return (nil, bytes) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return (context.makeImage().flatMap(Pixels.init), bytes)
    }

    let plain = await writeGIF("plain.gif", dithered: false)
    let smooth = await writeGIF("smooth.gif", dithered: true)

    if let plainPixels = plain.pixels, let smoothPixels = smooth.pixels {
        let plainRun = plainPixels.meanPlateauRun()
        let smoothRun = smoothPixels.meanPlateauRun()

        // The banding this is all for. Stated as its own assertion so that
        // if GIF encoding ever stops banding, this fails loudly rather than
        // the fix silently becoming a no-op.
        check("undithered GIF really does band", plainRun > sourceRun * 2,
              String(format: "plateaus %.1f px vs the render's %.1f", plainRun, sourceRun))

        check("dithering brings the texture back to the render's",
              smoothRun < plainRun / 2 && smoothRun < sourceRun * 1.6,
              String(format: "plateaus %.1f px vs the render's %.1f", smoothRun, sourceRun))

        // Overshoot guard. Finer plateaus than the source means the noise
        // is now the dominant texture, which is the failure that looks like
        // success on every other metric.
        check("without over-dithering into noise", smoothRun > sourceRun * 0.6,
              String(format: "plateaus %.1f px vs the render's %.1f", smoothRun, sourceRun))

        // Under half a level out of 255 — an absolute bound on what the
        // noise is allowed to cost, not a number fitted to whatever the
        // current strength happens to produce.
        check("fidelity is unharmed",
              abs(sourcePixels.meanColorDifference(smoothPixels)
                  - sourcePixels.meanColorDifference(plainPixels)) < 0.5,
              String(format: "mean error %.2f dithered vs %.2f plain",
                     sourcePixels.meanColorDifference(smoothPixels),
                     sourcePixels.meanColorDifference(plainPixels)))
    }

    // The cost, asserted rather than hoped: LZW compresses flat runs, and
    // this removes them. Half again is the price; several times larger
    // would mean the strength had drifted.
    check("the file grows by a third, not a multiple",
          plain.bytes > 0 && Double(smooth.bytes) / Double(plain.bytes) < 1.8,
          String(format: "%.0f KB → %.0f KB (%.2fx)",
                 Double(plain.bytes) / 1024, Double(smooth.bytes) / 1024,
                 Double(smooth.bytes) / Double(max(plain.bytes, 1))))

    // The movie must never be dithered — it has no palette to fight.
    let movieURL = dir.appendingPathComponent("clip.mov")
    try? await AnimationExporter.write(
        frames: ditherFrames, gif: dir.appendingPathComponent("paired.gif"),
        movie: movieURL, gifDither: true
    )
    let movieBytes = ((try? Data(contentsOf: movieURL))?.count) ?? 0
    check("asking for a smooth GIF still writes a movie", movieBytes > 0,
          "\(movieBytes) bytes")

    if ran != expectedAssertions {
        print("  ✗ ran \(ran) assertions, expected \(expectedAssertions) — "
              + (ran < expectedAssertions
                 ? "one skipped itself because its inputs came back nil"
                 : "update expectedAssertions"))
        failed = true
    }

    return failed ? 1 : 0
}

/// How many assertions this check is supposed to run.
///
/// Every one of these targets builds its own inputs — render a frame,
/// write a GIF, decode it back — and every one of those steps is an
/// optional that can come back nil. Where that happens inside an `if let`
/// or a `guard ... else { continue }`, the assertions underneath simply
/// don't run and the gate still reports green. That is not hypothetical:
/// `Pixels` rejected wide-gamut renders for a while, and two assertions
/// about Ring Size quietly did nothing.
///
/// Counting them closes the whole class at once, including the paths
/// nobody has thought of yet. Adding an assertion without bumping this
/// fails too, which is the right direction to fail in.
let expectedAssertions = 42

/// A rendered frame, unpacked once into a flat byte buffer.
struct Pixels {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let data: [UInt8]
    let alphaFirst: Bool

    init?(_ image: CGImage) {
        guard image.bitsPerComponent == 8, image.bitsPerPixel == 32,
              let provider = image.dataProvider,
              let raw = provider.data,
              let base = CFDataGetBytePtr(raw) else { return nil }
        width = image.width
        height = image.height
        bytesPerRow = image.bytesPerRow
        data = Array(UnsafeBufferPointer(start: base, count: CFDataGetLength(raw)))
        let info = image.alphaInfo
        alphaFirst = info == .premultipliedFirst || info == .first || info == .noneSkipFirst
    }

    /// Redraws any `CGImage` into 8-bit premultiplied RGBA first.
    ///
    /// `ImageRenderer` is not obliged to hand back one layout: the same
    /// export path returns 8-bit/32bpp for one config and 16-bit/64bpp
    /// wide-gamut for another, and the plain initializer above rejects
    /// everything that isn't the former. A check that silently skips its
    /// own assertions on half the configs it's given is worse than one
    /// that fails.
    static func normalized(_ image: CGImage) -> Pixels? {
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage().flatMap(Pixels.init)
    }

    func matches(_ other: Pixels) -> Bool {
        width == other.width && height == other.height
            && bytesPerRow == other.bytesPerRow && data.count == other.data.count
    }

    private func offset(x: Int, y: Int) -> Int { y * bytesPerRow + x * 4 }

    func alpha(x: Int, y: Int) -> Int {
        Int(data[offset(x: x, y: y) + (alphaFirst ? 0 : 3)])
    }

    /// The three colour bytes, whichever end alpha sits at.
    func color(x: Int, y: Int) -> (Int, Int, Int) {
        let o = offset(x: x, y: y) + (alphaFirst ? 1 : 0)
        return (Int(data[o]), Int(data[o + 1]), Int(data[o + 2]))
    }

    /// Averaged over the lit pixels only — the dark field around the ring
    /// is identical in both frames and would swamp the signal.
    func meanColorDifference(_ other: Pixels) -> Double {
        var total = 0.0
        var counted = 0
        for y in stride(from: 0, to: height, by: 2) {
            for x in stride(from: 0, to: width, by: 2) where alpha(x: x, y: y) > 32 {
                let (r0, g0, b0) = color(x: x, y: y)
                let (r1, g1, b1) = other.color(x: x, y: y)
                total += Double(abs(r0 - r1) + abs(g0 - g1) + abs(b0 - b1)) / 3
                counted += 1
            }
        }
        return counted > 0 ? total / Double(counted) : 0
    }

    func alphaProfile(_ other: Pixels) -> (worst: Int, differing: Int, lit: Int) {
        var worst = 0, differing = 0, lit = 0
        for y in 0..<height {
            for x in 0..<width {
                let d = abs(alpha(x: x, y: y) - other.alpha(x: x, y: y))
                if alpha(x: x, y: y) > 0 { lit += 1 }
                if d > 0 { differing += 1 }
                worst = max(worst, d)
            }
        }
        return (worst, differing, lit)
    }

    /// What's inside the ring, and what's on it.
    ///
    /// The band is found by scanning rather than assumed, so this holds at
    /// any line width or canvas size.
    func holeAndBand() -> (hole: Int, partialHole: Int, band: Int) {
        let cx = width / 2
        let cy = height / 2
        var bandY = 0
        var best = 0
        for y in 0..<cy where alpha(x: cx, y: y) > best {
            best = alpha(x: cx, y: y)
            bandY = y
        }
        let bandR = Double(cy - bandY) / Double(width)
        var hole = 0
        var partialHole = 0
        var band = 0
        for y in Swift.stride(from: 0, to: height, by: 2) {
            for x in Swift.stride(from: 0, to: width, by: 2) {
                let dx = Double(x - cx), dy = Double(y - cy)
                let r = (dx * dx + dy * dy).squareRoot() / Double(width)
                let a = alpha(x: x, y: y)
                if r < bandR * 0.45 {
                    if a > 128 { hole += 1 } else if a > 8 { partialHole += 1 }
                }
                if abs(r - bandR) < 0.012, a > 128 { band += 1 }
            }
        }
        return (hole, partialHole, band)
    }

    /// The brightest point on the band, and a point well outside it in the
    /// halo — sampled on the same radius so they describe the same part of
    /// the ring.
    func bandAndHalo() -> (band: (Int, Int, Int), halo: (Int, Int, Int)) {
        let cx = width / 2
        let cy = height / 2
        var bandY = 0
        var best = 0
        for y in 0..<cy where alpha(x: cx, y: y) > best {
            best = alpha(x: cx, y: y)
            bandY = y
        }
        return (color(x: cx, y: bandY), color(x: cx, y: max(bandY - 40, 2)))
    }

    /// How far you travel outward through the glow, on average, before the
    /// colour changes.
    ///
    /// This is the banding metric. A palette-quantized gradient holds one
    /// colour across a wide stretch and then steps — long runs with visible
    /// seams — while the same gradient rendered in full colour changes
    /// every few pixels. Eight radials, so one unlucky angle can't decide
    /// the answer.
    func meanPlateauRun(radials: Int = 8) -> Double {
        var lengths: [Int] = []
        let cx = width / 2
        let cy = height / 2
        for step in 0..<radials {
            let angle = Double(step) / Double(radials) * 2 * .pi
            var previous: (Int, Int, Int)?
            var run = 0
            for r in stride(from: 40, to: min(width, height) / 2, by: 1) {
                let x = cx + Int(cos(angle) * Double(r))
                let y = cy + Int(sin(angle) * Double(r))
                guard x >= 0, x < width, y >= 0, y < height else { continue }
                let here = color(x: x, y: y)
                if let last = previous, last == here {
                    run += 1
                } else {
                    if run > 0 { lengths.append(run) }
                    run = 1
                }
                previous = here
            }
            if run > 0 { lengths.append(run) }
        }
        guard !lengths.isEmpty else { return 0 }
        return Double(lengths.reduce(0, +)) / Double(lengths.count)
    }

    /// Walks a circle through the middle of the band and reports the mean
    /// colour change from one sample to the next.
    ///
    /// The radius is found rather than assumed: it's the ring that carries
    /// the alpha, so the brightest row of the frame's vertical centre line
    /// says where the band is, and that holds whatever the line width or
    /// canvas size happen to be.
    func meanAngularStep(samples: Int = 360) -> Double {
        let cx = Double(width) / 2
        let cy = Double(height) / 2
        var radius = 0.0
        var best = 0
        for y in 0..<Int(cy) {
            let value = alpha(x: Int(cx), y: y)
            if value > best { best = value; radius = cy - Double(y) }
        }
        guard radius > 1 else { return 0 }

        var previous: (Int, Int, Int)?
        var total = 0.0
        var counted = 0
        for i in 0..<samples {
            let angle = Double(i) / Double(samples) * 2 * .pi
            let x = Int((cx + cos(angle) * radius).rounded())
            let y = Int((cy + sin(angle) * radius).rounded())
            guard x >= 0, x < width, y >= 0, y < height, alpha(x: x, y: y) > 32 else {
                previous = nil
                continue
            }
            let here = color(x: x, y: y)
            if let last = previous {
                total += Double(abs(here.0 - last.0) + abs(here.1 - last.1) + abs(here.2 - last.2)) / 3
                counted += 1
            }
            previous = here
        }
        return counted > 0 ? total / Double(counted) : 0
    }
}

let status = await run()
exit(status)
