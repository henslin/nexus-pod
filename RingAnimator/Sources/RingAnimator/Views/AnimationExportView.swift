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
    let colorScheme: ColorScheme
    /// Dismisses the sheet — passed in rather than using `@Environment(\.dismiss)`
    /// so the Cancel button can be disabled (not hidden) while exporting,
    /// matching the "Exporting…" progress state below.
    let onDismiss: () -> Void

    @State private var exportGIF = true
    @State private var exportMovie = true
    @State private var loopCount = 2
    @State private var isExporting = false
    @State private var progress: Double = 0
    @State private var errorMessage: String?

    private var loopDuration: TimeInterval {
        AnimationExporter.naturalLoopDuration(for: config)
    }

    private var totalDuration: TimeInterval {
        loopDuration * Double(loopCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Export Animation")
                .font(.headline)

            Text("Renders the current live preview to a file — \(String(format: "%.1f", loopDuration))s per loop at \(Int(AnimationExporter.fps))fps.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Animated GIF", isOn: $exportGIF)
                Toggle("Movie (.mov)", isOn: $exportMovie)
            }
            .toggleStyle(.checkbox)

            Stepper(value: $loopCount, in: 1...8) {
                HStack {
                    Text("Loops")
                    Spacer()
                    Text("\(loopCount) (\(String(format: "%.1f", totalDuration))s)")
                        .foregroundStyle(.secondary)
                }
            }

            if config.particlesEnabled {
                Label("Particles can't be captured deterministically and will be off in the export.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let baseURL = url.deletingPathExtension()
        errorMessage = nil
        isExporting = true
        progress = 0

        Task { @MainActor in
            let frames = await AnimationExporter.renderFrames(
                config: config,
                colorScheme: colorScheme,
                loopCount: loopCount,
                onProgress: { value in
                    // Frame rendering is roughly 80% of total export time
                    // (encoding, especially the GIF path, is comparatively
                    // fast) — scaling into that range keeps the bar from
                    // looking "done" long before the file actually is.
                    progress = value * 0.8
                }
            )

            guard !frames.isEmpty else {
                errorMessage = "Nothing to export — check the animation is running."
                isExporting = false
                return
            }

            do {
                if exportGIF {
                    try AnimationExporter.writeGIF(frames: frames, to: baseURL.appendingPathExtension("gif"))
                    progress = exportMovie ? 0.9 : 1
                }
                if exportMovie {
                    try await AnimationExporter.writeMovie(frames: frames, to: baseURL.appendingPathExtension("mov"))
                    progress = 1
                }
                isExporting = false
                onDismiss()
            } catch {
                errorMessage = error.localizedDescription
                isExporting = false
            }
        }
    }
}
