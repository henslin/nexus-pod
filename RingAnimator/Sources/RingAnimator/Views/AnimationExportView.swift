import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RingAnimatorCore

/// Sheet presented from `PhoneMockupView`'s controls bar — renders the
/// current live ring animation to an animated GIF and/or a `.mov` movie
/// file. See `AnimationExporter` (RingAnimatorCore) for the actual
/// rendering/encoding; this view is just the format/loop-count controls,
/// progress bar, and `NSSavePanel` wiring around it.
struct AnimationExportView: View {
    @ObservedObject var config: RingConfig
    /// The sequence, if one exists. An empty timeline hides the source
    /// picker entirely, so this sheet is unchanged for anyone not using
    /// the feature.
    var timeline: RingTimeline = RingTimeline()
    let colorScheme: ColorScheme
    /// The finish the canvas is wearing, so the sheet opens on the phone
    /// you were just looking at.
    var deviceFinish: AnimationExporter.DeviceFinish = .silver
    /// Dismisses the sheet — passed in rather than using `@Environment(\.dismiss)`
    /// so the Cancel button can be disabled (not hidden) while exporting,
    /// matching the "Exporting…" progress state below.
    let onDismiss: () -> Void

    @State private var exportGIF = true
    @State private var exportMovie = true
    @State private var gifDither = false
    @State private var loopCount = 2
    @State private var captureParticles = false
    /// Canvas, appearance and transparency — shared with the batch sheet
    /// (see `ExportCanvasSettings`). Appearance is seeded from the canvas's
    /// current one, that being what you were just looking at, but free to
    /// differ so a dark clip doesn't mean flipping the canvas and flipping
    /// it back.
    @State private var canvasSettings: ExportCanvasSettings
    @State private var isExporting = false
    @State private var progress: Double = 0
    @State private var errorMessage: String?
    @State private var source: ExportSource

    /// Defaults to the timeline when there is one. If you've built a
    /// sequence and hit Export, the sequence is what you meant — falling
    /// back to the single live ring would quietly export something else.
    init(
        config: RingConfig,
        timeline: RingTimeline = RingTimeline(),
        colorScheme: ColorScheme,
        deviceFinish: AnimationExporter.DeviceFinish = .silver,
        onDismiss: @escaping () -> Void
    ) {
        self.config = config
        self.timeline = timeline
        self.colorScheme = colorScheme
        self.deviceFinish = deviceFinish
        self.onDismiss = onDismiss
        _source = State(initialValue: timeline.isEmpty ? .live : .timeline)
        // Deliberately not seeded from the canvas any more. An export
        // mostly lands somewhere light, and starting from "ring only, no
        // phone, light" is the plain result — the canvas's own dark
        // preview and titanium finish are choices about *previewing*.
        _canvasSettings = State(initialValue: ExportCanvasSettings())
    }

    private enum ExportSource: String, CaseIterable, Identifiable {
        case live = "Live Ring"
        case timeline = "Timeline"
        var id: String { rawValue }
    }

    private var isTimelineExport: Bool {
        source == .timeline && !timeline.isEmpty
    }

    /// One pass. For the timeline that's the whole sequence; for the live
    /// ring it's one cycle of whatever it's doing.
    private var loopDuration: TimeInterval {
        isTimelineExport ? timeline.duration : AnimationExporter.naturalLoopDuration(for: config)
    }

    /// True if anything being exported has particles on — they can't be
    /// rendered deterministically and get forced off, which is worth
    /// saying before someone exports and wonders where they went. Checks
    /// every step, not just the live config, since a sequence can have
    /// particles on in one step and off in the rest.
    private var particlesWillBeDropped: Bool {
        isTimelineExport
            ? timeline.segments.contains { $0.snapshot.particlesEnabled }
            : config.particlesEnabled
    }

    /// The two formats behave differently enough here to be worth saying
    /// before the export rather than after: HEVC carries real partial
    /// alpha, GIF has one transparent colour and nothing in between, so a
    /// GIF's glow and anti-aliased edges get a hard cut.
    private var transparencyNote: String {
        if exportGIF && exportMovie {
            return "The movie keeps soft edges and glow. GIF transparency is 1-bit, so its edges will be harder."
        } else if exportGIF {
            return "GIF transparency is 1-bit — the glow drops out and edges will be harder than on screen."
        } else {
            return "Written as HEVC with alpha — plays transparent in QuickTime, Keynote, and AVPlayer."
        }
    }

    /// Recording drives a live preview window, so it follows one config
    /// playing in real time — a multi-step timeline has no such window to
    /// point a capture at.
    private var canCaptureParticles: Bool {
        !isTimelineExport
    }

    private var particleNote: String {
        if !canCaptureParticles {
            return "Particles can't be rendered frame by frame and will be off in this export."
        }
        if captureParticles {
            return "Records the preview as it plays, so this takes the full \(String(format: "%.1f", totalDuration))s and needs Screen Recording permission. A preview window appears while it records."
        }
        return "Particles can't be rendered frame by frame, so they'll be off unless you record them."
    }

    private var totalDuration: TimeInterval {
        loopDuration * Double(loopCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Export Animation")
                .font(.headline)

            Text(isTimelineExport
                 ? "Renders the \(timeline.segments.count)-step sequence to a file — \(String(format: "%.1f", loopDuration))s per pass at \(Int(AnimationExporter.fps))fps."
                 : "Renders the current live preview to a file — \(String(format: "%.1f", loopDuration))s per loop at \(Int(AnimationExporter.fps))fps.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !timeline.isEmpty {
                Picker("Source", selection: $source) {
                    ForEach(ExportSource.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Form {
                Section("Animation Type") {
                    // Checkboxes, not switches: you are choosing which
                    // files to write, not turning a feature on. Ticking
                    // both keeps the one-of-each pass without "Both"
                    // having to exist as its own option.
                    Toggle("Animated GIF", isOn: $exportGIF)
                    // A GIF-only refinement, so it sits under the GIF it
                    // refines and greys out with it — the same shape as
                    // Include UI enabling the tab picker.
                    Toggle("Smooth GIF gradients", isOn: $gifDither)
                        .disabled(!exportGIF)
                        .padding(.leading, 18)
                        .help("Dithers the frames so gradients don't band on GIF's 256-colour palette. Roughly a third larger.")
                    Toggle("Movie (.mov)", isOn: $exportMovie)
                }
                .toggleStyle(.checkbox)

                ExportCanvasOptionsView(settings: $canvasSettings)

                Section("Duration") {
                    Stepper(value: $loopCount, in: 1...8) {
                        Text("\(loopCount == 1 ? "1 loop" : "\(loopCount) loops") · \(String(format: "%.1f", totalDuration))s")
                    }
                    if canvasSettings.effectiveTransparent {
                        Text(transparencyNote)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .formStyle(.grouped)

            if particlesWillBeDropped {
                VStack(alignment: .leading, spacing: 6) {
                    if canCaptureParticles {
                        Toggle("Record particles from the live preview", isOn: $captureParticles)
                            .toggleStyle(.checkbox)
                    }
                    Label(particleNote, systemImage: captureParticles ? "record.circle" : "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if isExporting {
                ProgressView(value: progress) {
                    Text("Rendering frames…")
                        .font(.caption)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { onDismiss() }
                    .disabled(isExporting)
                    .ringGlassButtonStyle()
                Button("Export…") { beginExport() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isExporting || (!exportGIF && !exportMovie))
                    .ringGlassButtonStyle()
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            // The default belongs to *this* opening of the sheet, not to
            // whenever the view was first constructed. `@State`'s initial
            // value is applied once; open Export while the sequence is
            // empty, then build one and open it again, and the picker is
            // still sitting on Live Ring — so Export quietly writes the
            // selected step instead of the sequence you just built.
            source = timeline.isEmpty ? .live : .timeline
        }
    }


    private func beginExport() {
        let panel = NSSavePanel()
        panel.prompt = "Export"
        panel.nameFieldStringValue = "Nexus Animation"
        // Only offering the leading format as the panel's own extension —
        // when both are requested, the second file is derived from
        // whatever base name/directory the user picks here (see below)
        // rather than prompting twice.
        if exportGIF {
            panel.allowedContentTypes = [.gif]
        } else if exportMovie {
            panel.allowedContentTypes = [.quickTimeMovie]
        }
        ExportLog.note("single sheet: gif=\(exportGIF) movie=\(exportMovie) dither=\(gifDither) particles=\(captureParticles) transparent=\(canvasSettings.effectiveTransparent) loops=\(loopCount)")
        let response = panel.runModal()
        ExportLog.note("  panel returned \(response.rawValue) (OK is \(NSApplication.ModalResponse.OK.rawValue)), url=\(panel.url?.path ?? "nil")")
        guard response == .OK, let url = panel.url else {
            ExportLog.note("  bailed out before writing anything")
            return
        }

        let baseURL = url.deletingPathExtension()
        errorMessage = nil
        isExporting = true
        progress = 0

        Task { @MainActor in
            let gifURL = exportGIF ? baseURL.appendingPathExtension("gif") : nil
            let movieURL = exportMovie ? baseURL.appendingPathExtension("mov") : nil
            // Rendering and encoding are one pass now, so the bar is the
            // real fraction rather than a guess split between two phases.
            let onProgress: @MainActor (Double) -> Void = { progress = $0 }
            ExportLog.note("  gif=\(gifURL?.path ?? "nil") movie=\(movieURL?.path ?? "nil") timeline=\(isTimelineExport)")

            do {
                if captureParticles && canCaptureParticles {
                    // The recorded path can't stream: its frames arrive in
                    // real time from the capture, and there is nothing to
                    // write until they have.
                    let frames = try await LivePreviewRecorder.record(
                        config: config,
                        colorScheme: canvasSettings.appearance,
                        duration: totalDuration,
                        transparent: canvasSettings.effectiveTransparent,
                        canvas: canvasSettings.canvas,
                        onProgress: onProgress
                    )
                    try await AnimationExporter.write(
                        frames: frames, gif: gifURL, movie: movieURL,
                        transparent: canvasSettings.effectiveTransparent,
                        gifDither: gifURL != nil && gifDither
                    )
                } else if isTimelineExport {
                    try await AnimationExporter.export(
                        timeline: timeline,
                        colorScheme: canvasSettings.appearance,
                        loopCount: loopCount,
                        transparent: canvasSettings.effectiveTransparent,
                        canvas: canvasSettings.canvas,
                        gif: gifURL, movie: movieURL,
                        gifDither: gifURL != nil && gifDither,
                        onProgress: onProgress
                    )
                } else {
                    try await AnimationExporter.export(
                        config: config,
                        colorScheme: canvasSettings.appearance,
                        loopCount: loopCount,
                        transparent: canvasSettings.effectiveTransparent,
                        canvas: canvasSettings.canvas,
                        gif: gifURL, movie: movieURL,
                        gifDither: gifURL != nil && gifDither,
                        onProgress: onProgress
                    )
                }
                for written in [gifURL, movieURL].compactMap({ $0 }) {
                    let size = (try? written.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? nil
                    ExportLog.note("  wrote \(written.lastPathComponent): \(size.map(String.init) ?? "MISSING") bytes")
                }
                isExporting = false
                onDismiss()
            } catch {
                ExportLog.note("  THREW: \(error)")
                errorMessage = error.localizedDescription
                isExporting = false
            }
        }
    }
}
