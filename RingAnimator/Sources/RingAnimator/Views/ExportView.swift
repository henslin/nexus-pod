import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RingAnimatorCore

/// Language picker + one full-width code pane, instead of three fixed
/// ~420pt-minimum columns side by side in an `HSplitView` — the old layout
/// meant SwiftUI/Compose/Web (and now Blender) never all fit in a typical
/// window at once. A segmented control (the same pattern `ContentView`
/// already uses for its own Preview/Export toggle) shows one language at a
/// time, so whichever one you're looking at always has the full window
/// width to itself and reflows naturally as you resize.
struct ExportView: View {
    @ObservedObject var config: RingConfig

    enum ExportLanguage: String, CaseIterable, Identifiable {
        case swift = "SwiftUI"
        case compose = "Compose"
        case web = "Web"
        case blender = "Blender"

        var id: String { rawValue }
    }

    @State private var language: ExportLanguage = .swift
    @State private var importErrorMessage: String?
    @State private var importSuccessMessage: String?

    private var swiftCode: String { CodeGenerators.swiftUICode(config: config) }
    private var composeCode: String { CodeGenerators.composeCode(config: config) }
    private var webCode: String { CodeGenerators.webCode(config: config) }
    private var blenderCode: String { CodeGenerators.blenderCode(config: config) }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Language", selection: $language) {
                ForEach(ExportLanguage.allCases) { lang in
                    Text(lang.rawValue).tag(lang)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)
            .padding(.top, 10)

            // Said out loud rather than left to be discovered: the
            // generators draw each animation the continuous way, so a
            // config using Diode Mode or a non-round diode shape exports
            // as something that doesn't match the preview. Better to state
            // the gap than to hand someone code that quietly differs from
            // what they designed.
            if config.diodeModeEnabled || config.diodeShape != .round {
                Label(
                    config.diodeModeEnabled
                        ? "Diode Mode isn't in the exported code yet — this exports the continuous form of \(config.animationType.rawValue)."
                        : "Diode shape isn't in the exported code yet — exported diodes are round.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 8)
            }

            switch language {
            case .swift:
                codePane(title: "SwiftUI · iOS", code: swiftCode, filename: "ThinkingRingView.swift")
            case .compose:
                codePane(title: "Jetpack Compose · Android", code: composeCode, filename: "ThinkingRingView.kt")
            case .web:
                codePane(title: "HTML/Canvas · Web", code: webCode, filename: "thinking-ring.html")
            case .blender:
                codePane(title: "Python · Blender", code: blenderCode, filename: "ring_pod_blender.py", allowsImport: true)
            }
        }
        .alert(
            "Couldn't Import",
            isPresented: Binding(get: { importErrorMessage != nil }, set: { if !$0 { importErrorMessage = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(importErrorMessage ?? "")
        }
        .alert(
            "Imported",
            isPresented: Binding(get: { importSuccessMessage != nil }, set: { if !$0 { importSuccessMessage = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(importSuccessMessage ?? "")
        }
    }

    private func codePane(title: String, code: String, filename: String, allowsImport: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                // These sit on their own, not inside a List/Form/Toolbar
                // (which already get Liquid Glass chrome automatically) —
                // so they opt into the native glass button style explicitly,
                // grouped in a container so they blend together correctly
                // rather than rendering as separate glass blobs. Package.swift
                // can't declare a macOS 26 minimum in this Xcode beta (see
                // TabBarPreview.swift for the full explanation), so this
                // still needs a runtime check + plain-button fallback.
                if #available(macOS 26.0, *) {
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            if allowsImport {
                                Button("Import…") { importBlender() }
                                    .buttonStyle(.glass)
                            }
                            Button("Copy") { copy(code) }
                                .buttonStyle(.glass)
                            Button("Save…") { save(code, filename: filename) }
                                .buttonStyle(.glass)
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        if allowsImport {
                            Button("Import…") { importBlender() }
                        }
                        Button("Copy") { copy(code) }
                        Button("Save…") { save(code, filename: filename) }
                    }
                }
            }
            ScrollView {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func save(_ text: String, filename: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        if panel.runModal() == .OK, let url = panel.url {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Reads a `.py` file — either one Nexus exported, or a teammate's
    /// hand-edited copy of one — and applies whatever `NEXUS_PARAMS` it
    /// finds straight onto the live ring, the same "load it and see it"
    /// pattern `SavedPresetsView` uses for its own Import.
    private func importBlender() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "py") ?? .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            importErrorMessage = "Couldn't read that file."
            return
        }
        switch CodeGenerators.applyBlenderCode(text, to: config) {
        case .success:
            importSuccessMessage = "Updated the ring from \(url.lastPathComponent)."
        case .failure:
            importErrorMessage = "That doesn't look like a Nexus Blender export — couldn't find a NEXUS_PARAMS block to read."
        }
    }
}
