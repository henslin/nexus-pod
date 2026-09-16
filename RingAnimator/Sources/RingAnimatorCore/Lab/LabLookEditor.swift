import SwiftUI

// Choosing and tuning a slot's look without leaving Q Branch.
//
// Chris, 2026-09-16: "reuse the menu we made that includes all of the
// animated thumbnails. Then, when you select one, reuse the parameters
// glyph on the right and edit/save it in place. Sending you over to
// another part of the app feels disconnected." So: the style well's
// gallery (`StylesGalleryView`), for orbs — every base as a live pod,
// on its shelf — as a popover off the slot; and a second popover off
// the sliders glyph with the look's own knobs, bound straight into the
// spec. The bench is still there, one menu item down, for the full rail.

// MARK: - The gallery

/// Every orb base as a live pod, by family, plus saved presets. Pick one
/// and it becomes the slot's look, at its defaults (or the preset).
public struct LabOrbGallery: View {
    let frameAt: (Date) -> LabFrame
    @ObservedObject var config: RingConfig
    let current: LabLook?
    let onPick: (LabLook) -> Void
    @StateObject private var presets = LabPresetStore()
    @Environment(\.dismiss) private var dismiss

    public init(frameAt: @escaping (Date) -> LabFrame, config: RingConfig, current: LabLook?, onPick: @escaping (LabLook) -> Void) {
        self.frameAt = frameAt
        self.config = config
        self.current = current
        self.onPick = onPick
    }

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 10)]
    /// One clock for the gallery; only the cells on screen draw from it
    /// (Chris, 2026-09-16: "show the thumbnail animations, but only the
    /// ones in view"). The lazy grid builds cells as they scroll into
    /// view, and each one stops listening when it scrolls out.
    @StateObject private var clock = LabThumbClock()

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Every orb at its defaults. Pick one for this slot; the sliders beside the slot tune it.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                let saved = presets.presets.filter { LabExperiment(rawValue: $0.experiment)?.canBeHero ?? false }
                if !saved.isEmpty {
                    group("Presets", "Looks you've saved on the bench.") {
                        ForEach(saved) { p in
                            let look = LabLook(experiment: p.experiment, values: p.values, post: p.post, palette: p.palette)
                            cell(look, name: "\(look.name) · \(p.name)")
                        }
                    }
                }
                ForEach(LabSection.orb.families, id: \.family) { family, bases in
                    group(family.title, nil) {
                        ForEach(bases.filter(\.canBeHero)) { e in
                            cell(LabLook(experiment: e.id), name: e.name)
                        }
                    }
                }
            }
            .padding(16)
        }
        .frame(width: 540, height: 600)
        .onAppear { clock.frameAt = frameAt; clock.run(true) }
        .onDisappear { clock.run(false) }
    }

    private func group<Content: View>(_ title: String, _ caption: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold))
            if let caption { Text(caption).font(.caption).foregroundStyle(.secondary) }
            LazyVGrid(columns: columns, spacing: 10) { content() }
        }
    }

    private func cell(_ look: LabLook, name: String) -> some View {
        let isCurrent = current?.experiment == look.experiment && current?.values == look.values
        return Button {
            onPick(look)
            dismiss()
        } label: {
            VStack(spacing: 6) {
                LabGalleryPod(clock: clock, look: look, config: config, still: frameAt(Date()).withTime(1.7))
                    .frame(width: 56, height: 56)
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isCurrent ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isCurrent ? Color.accentColor : .clear, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
    }
}

/// One gallery cell's pod: on the clock while it's on screen, a still
/// once it has scrolled out of view.
private struct LabGalleryPod: View {
    @ObservedObject var clock: LabThumbClock
    let look: LabLook
    @ObservedObject var config: RingConfig
    let still: LabFrame
    @State private var visible = false

    var body: some View {
        let f = visible ? (clock.frame ?? still) : still
        LabPodGlass(config: config, dark: f.darkStage, flat: true) {
            LabHeroView(frame: f.applying(look, config: config), config: config, diameter: 62)
        }
        .scaleEffect(56 / 62)
        .onAppear { visible = true }
        .onDisappear { visible = false }
    }
}

// MARK: - The editor

/// A look's knobs, bound straight into the spec: the shared knobs, the
/// experiment's own, the post stack. What the bench's rail does, in a
/// popover, for one slot.
struct LabLookEditor: View {
    @Binding var look: LabLook
    let frameAt: (Date) -> LabFrame
    @ObservedObject var config: RingConfig
    /// The bench, for "the full rail".
    let onBench: () -> Void
    @State private var openPost: LabPostEffect?
    @Environment(\.dismiss) private var dismiss

    private var experiment: LabExperiment? { look.experimentCase }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let experiment, !experiment.parameters.isEmpty {
                        sectionTitle(experiment.name)
                        knobs(of: experiment)
                    }
                    if experiment?.canBeHero == true {
                        sectionTitle("Post Effects").padding(.top, 8)
                        postStack
                        sectionTitle("Stage").padding(.top, 8)
                        LabSlider(title: "Intensity", value: $look.intensity, range: 0...1)
                        LabSlider(title: "Speed", value: $look.speed, range: 0.1...3, format: "%.1f×")
                        LabSlider(title: "Fill", value: $look.fill, range: 0...1.3)
                        HStack(spacing: 8) {
                            Text("Palette").font(.callout).foregroundStyle(.secondary).frame(width: LabRailMetrics.labelWidth, alignment: .leading)
                            Picker("", selection: Binding(get: { look.paletteCase }, set: { look.palette = $0.rawValue })) {
                                ForEach(LabPalette.allCases) { Text($0.label).tag($0) }
                            }
                            .labelsHidden().pickerStyle(.menu).controlSize(.small)
                            Spacer(minLength: 0)
                        }
                        HStack(spacing: 8) {
                            Text("Glyph").font(.callout).foregroundStyle(.secondary).frame(width: LabRailMetrics.labelWidth, alignment: .leading)
                            TextField("SF Symbol", text: $look.glyph).textFieldStyle(.roundedBorder).controlSize(.small)
                        }
                    }
                }
                .padding(14)
            }
            Divider()
            HStack {
                Button("Reset") {
                    look = LabLook(experiment: look.experiment)
                }
                .help("Back to the experiment's defaults")
                Button("Full Rail on the Bench…") { dismiss(); onBench() }
                    .help("Every control, on the stage — Use brings it back here")
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
            .padding(10)
        }
        .frame(width: 360, height: 520)
    }

    private var header: some View {
        HStack(spacing: 10) {
            TimelineView(.periodic(from: .now, by: 1 / 30)) { timeline in
                let f = frameAt(timeline.date)
                LabPodGlass(config: config, dark: f.darkStage, flat: true) {
                    LabHeroView(frame: f.applying(look, config: config), config: config, diameter: 62)
                }
                .scaleEffect(44 / 62)
                .frame(width: 44, height: 44)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(look.title).font(.headline)
                Text(experiment?.technology ?? "").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(.subheadline.weight(.semibold))
    }

    private func binding(_ p: LabParameter, of e: LabExperiment) -> Binding<Double> {
        let key = "\(e.id).\(p.id)"
        return Binding(get: { look.values[key] ?? p.defaultValue }, set: { look.values[key] = $0 })
    }

    private func knobs(of e: LabExperiment) -> some View {
        let params = e.parameters
        return ForEach(Array(params.enumerated()), id: \.element.id) { i, p in
            if let g = p.group, i == 0 || params[i - 1].group != g,
               !(g == p.name && (i + 1 >= params.count || params[i + 1].group != g)) {
                Text(g).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, i == 0 ? 0 : 6)
            }
            LabKnob(parameter: p, value: binding(p, of: e))
        }
    }

    private var postStack: some View {
        VStack(alignment: .leading, spacing: 6) {
            if look.posts.isEmpty {
                Text("Nothing stacked.").font(.caption).foregroundStyle(.tertiary)
            }
            ForEach(look.posts) { effect in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) { openPost = openPost == effect ? nil : effect }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .rotationEffect(.degrees(openPost == effect ? 90 : 0))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 10)
                                Text(effect.experiment.name).font(.callout)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button {
                            look.post.removeAll { $0 == effect.rawValue }
                            if openPost == effect { openPost = nil }
                        } label: { Image(systemName: "xmark") }
                            .buttonStyle(.borderless).font(.caption)
                    }
                    if openPost == effect {
                        knobs(of: effect.experiment).padding(.leading, 16)
                    }
                }
            }
            Menu {
                ForEach(LabPostEffect.allCases.filter { !look.posts.contains($0) }) { effect in
                    Button {
                        look.post.append(effect.rawValue)
                        openPost = effect
                    } label: { Label(effect.experiment.name, systemImage: effect.experiment.symbol) }
                }
            } label: { Label("Add Effect", systemImage: "plus") }
                .menuStyle(.borderlessButton).fixedSize().font(.caption)
        }
    }
}
