import SwiftUI
import AppKit
import RingAnimatorCore

/// Renders every animation in a list to GIF and/or movie, into one folder.
///
/// The single-file sheet exports whatever the ring is showing. With a
/// pattern library imported that's sixty-nine trips through a save panel to
/// get a folder of clips for a deck, which is the kind of thing nobody does
/// twice.
///
/// Rendering is main-actor bound — `ImageRenderer` drives AppKit — so this
/// can't be parallelised. It runs one animation at a time and reports which,
/// because a bar with no name on it during a sixty-nine item render tells
/// you nothing about whether it's stuck.
struct BatchExportView: View {
    let presets: [RingPreset]
    let sectionName: String
    let colorScheme: ColorScheme
    let onDismiss: () -> Void

    @State private var exportGIF = true
    @State private var exportMovie = false
    @State private var loopCount = 2
    @State private var isExporting = false
    @State private var completed = 0
    @State private var currentName = ""
    @State private var frameProgress: Double = 0
    @State private var failures: [String] = []
    @State private var finishedURL: URL?
    @State private var isCancelled = false
    @State private var items: [ExportItem] = []

    /// Past this many, one bar and a name stops being useful — you can't
    /// tell what's left, what already failed, or whether the one taking a
    /// while is the one you cared about. Below it, a queue of sixty-nine
    /// rows for a job of three would be the opposite problem.
    private static let queueThreshold = 20

    private var showsQueue: Bool { presets.count > Self.queueThreshold }

    struct ExportItem: Identifiable {
        let id: UUID
        let name: String
        var state: State = .waiting

        enum State: Equatable {
            case waiting
            case rendering(Double)
            case done
            case failed
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Export All of \(sectionName)")
                    .font(.headline)
                Text(presets.count == 1
                     ? "1 animation, into a folder you choose."
                     : "\(presets.count) animations, into a folder you choose.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if isExporting {
                progressSection
            } else if let finishedURL {
                doneSection(finishedURL)
            } else {
                optionsSection
            }

            HStack {
                Spacer()
                if isExporting {
                    Button("Cancel") { isCancelled = true }
                        .ringGlassButtonStyle()
                } else if finishedURL != nil {
                    Button("Done") { onDismiss() }
                        .keyboardShortcut(.defaultAction)
                        .ringGlassButtonStyle()
                } else {
                    Button("Cancel") { onDismiss() }
                        .ringGlassButtonStyle()
                    Button("Choose Folder…") { start() }
                        .keyboardShortcut(.defaultAction)
                        .ringGlassButtonStyle()
                        .disabled(!exportGIF && !exportMovie)
                }
            }
        }
        .padding(20)
        .frame(width: showsQueue ? 460 : 420)
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("GIF", isOn: $exportGIF)
            Toggle("Movie (.mov)", isOn: $exportMovie)
            Stepper(value: $loopCount, in: 1...8) {
                Text("Loops per file: \(loopCount)")
            }
            Text("Files are named after each animation. Existing files with the same name are replaced.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Whole-run progress: finished items, plus how far into the
            // current one. A bar that only moved once per animation would
            // sit still for a long time on the slow ones.
            ProgressView(value: overallProgress)
            Text("\(min(completed + 1, presets.count)) of \(presets.count) · \(currentName)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if showsQueue {
                Divider()
                queue
            }
        }
    }

    /// A row per animation, for runs long enough that the summary line
    /// isn't enough to know what's happening.
    private var queue: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(items) { item in
                        queueRow(item).id(item.id)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 240)
            // Follow the one being rendered, so the queue doesn't sit at
            // the top while work happens forty rows down.
            .onChange(of: completed) { _, _ in
                guard let active = items.first(where: {
                    if case .rendering = $0.state { return true }
                    return false
                }) else { return }
                withAnimation { proxy.scrollTo(active.id, anchor: .center) }
            }
        }
    }

    private func queueRow(_ item: ExportItem) -> some View {
        HStack(spacing: 10) {
            switch item.state {
            case .waiting:
                Image(systemName: "circle.dotted")
                    .foregroundStyle(.tertiary)
            case .rendering:
                Image(systemName: "circle.dashed")
                    .foregroundStyle(Color.accentColor)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.green)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.orange)
            }

            Text(item.name)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(item.state == .waiting ? .secondary : .primary)

            Spacer(minLength: 8)

            if case .rendering(let value) = item.state {
                ProgressView(value: value)
                    .progressViewStyle(.linear)
                    .frame(width: 90)
            }
        }
        .frame(minHeight: 18)
    }

    private func doneSection(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                failures.isEmpty
                    ? "Exported \(completed) of \(presets.count)."
                    : "Exported \(completed) of \(presets.count) — \(failures.count) failed.",
                systemImage: failures.isEmpty ? "checkmark.circle" : "exclamationmark.triangle"
            )
            .foregroundStyle(failures.isEmpty ? Color.green : Color.orange)

            if !failures.isEmpty {
                Text(failures.prefix(4).joined(separator: ", ")
                     + (failures.count > 4 ? "…" : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            .ringGlassButtonStyle()
        }
    }

    private var overallProgress: Double {
        guard !presets.isEmpty else { return 0 }
        return (Double(completed) + frameProgress) / Double(presets.count)
    }

    private func start() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Export Here"
        panel.message = "Choose a folder for \(presets.count) animation\(presets.count == 1 ? "" : "s")"
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        isExporting = true
        completed = 0
        failures = []
        isCancelled = false
        items = presets.map { ExportItem(id: $0.id, name: $0.name) }

        Task { @MainActor in
            for (index, preset) in presets.enumerated() {
                if isCancelled { break }
                currentName = preset.name
                frameProgress = 0
                items[index].state = .rendering(0)

                // A fresh config per preset rather than one reused: these
                // carry a recorded stream and a firmware field, and leaving
                // a previous animation's settings in place would export the
                // wrong thing for anything that doesn't set every field.
                let config = RingConfig()
                preset.apply(to: config)

                let frames = await AnimationExporter.renderFrames(
                    config: config,
                    colorScheme: colorScheme,
                    loopCount: loopCount
                ) { value in
                    frameProgress = value * 0.9
                    items[index].state = .rendering(value)
                }

                guard !frames.isEmpty else {
                    failures.append(preset.name)
                    items[index].state = .failed
                    completed += 1
                    continue
                }

                let base = folder.appendingPathComponent(safeFileName(preset.name))
                do {
                    if exportGIF {
                        try AnimationExporter.writeGIF(
                            frames: frames, to: base.appendingPathExtension("gif")
                        )
                    }
                    if exportMovie {
                        let movie = base.appendingPathExtension("mov")
                        // AVAssetWriter refuses to start when something is
                        // already at the destination, which on a re-run of
                        // the same folder is every file.
                        try? FileManager.default.removeItem(at: movie)
                        try await AnimationExporter.writeMovie(frames: frames, to: movie)
                    }
                    items[index].state = .done
                } catch {
                    failures.append(preset.name)
                    items[index].state = .failed
                }
                completed += 1
                frameProgress = 0
            }

            isExporting = false
            finishedURL = folder
        }
    }

    /// `/` and `:` are the two the filesystem and Finder disagree about, and
    /// a use case named "Wi-Fi / Pairing" is not unlikely.
    private func safeFileName(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled" : cleaned
    }
}
