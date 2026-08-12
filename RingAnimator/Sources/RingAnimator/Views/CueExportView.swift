import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RingAnimatorCore

/// Code export for a single Cue Library entry — the Cue Library's
/// counterpart to Nexus's `ExportView`. Bakes in whichever
/// `LEDPatternStyle` (plus every motion-effect/particle/aberration tweak)
/// the cue currently has, exactly like `ExportView` bakes in Nexus's
/// currently-selected `RingAnimationType` — not a runtime
/// switch over all 14 styles, just this cue's current look, portable to
/// iOS/Android/Web/Blender. Same segmented-control-plus-one-full-width-pane
/// layout as `ExportView`, for the same reason: a fixed-minimum-width
/// `HSplitView` of 4 languages never all fit in a typical window at once.
struct CueExportView: View {
    let cue: LEDCue
    @ObservedObject var store: LEDCueStore

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

    private var parameters: LEDCueParameters { store.parameters(for: cue) }
    private var swiftCode: String { CodeGenerators.swiftUICueCode(cue: cue, parameters: parameters) }
    private var composeCode: String { CodeGenerators.composeCueCode(cue: cue, parameters: parameters) }
    private var webCode: String { CodeGenerators.webCueCode(cue: cue, parameters: parameters) }
    private var blenderCode: String { CodeGenerators.blenderCueCode(cue: cue, parameters: parameters) }

    private var fileBase: String { cue.id }

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

            switch language {
            case .swift:
                codePane(title: "SwiftUI · iOS", code: swiftCode, filename: "\(fileBase)-cue.swift")
            case .compose:
                codePane(title: "Jetpack Compose · Android", code: composeCode, filename: "\(fileBase)-cue.kt")
            case .web:
                codePane(title: "HTML/Canvas · Web", code: webCode, filename: "\(fileBase)-cue.html")
            case .blender:
                codePane(title: "Python · Blender", code: blenderCode, filename: "\(fileBase)-cue-blender.py", allowsImport: true)
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

    /// Reads a `.py` file — either one Nexus exported for this cue, or a
    /// teammate's hand-edited copy of one — and applies whatever
    /// `NEXUS_PARAMS` it finds back onto this cue, the same "load it and
    /// see it" pattern `ExportView`'s own Blender Import uses for Nexus.
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
        switch CodeGenerators.applyBlenderCueCode(text, to: parameters) {
        case .success(let updated):
            store.update(updated, for: cue)
            importSuccessMessage = "Updated \(cue.name) from \(url.lastPathComponent)."
        case .failure:
            importErrorMessage = "That doesn't look like a Nexus Blender export — couldn't find a NEXUS_PARAMS block to read."
        }
    }
}
