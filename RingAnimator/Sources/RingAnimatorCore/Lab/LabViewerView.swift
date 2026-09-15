import SwiftUI

/// The team viewer: every Lab experiment, full screen on a phone,
/// reacting to the room's voice, with a rating and a note per option —
/// so the team can hold each one, talk at it, and narrow the field.
///
/// Chris, 2026-09-15: "a separate iOS app that simply views these
/// animations and has them react to voice. A nice way for the team to
/// view and interact with each option to get a read on it."
///
/// Deliberately not the Mac Lab's panel: this is a *viewing* surface.
/// Swipe between experiments, tap the stage to advance the tappable
/// ones, mic on by default. The knobs are one sheet away for whoever
/// wants to push a slider, and the ratings export as text to paste
/// wherever the team talks.
public struct LabViewerView: View {
    @StateObject private var lab = LabState()
    @StateObject private var config = RingConfig()
    @StateObject private var audio = AudioSpectrumMonitor()
    @StateObject private var reviews = LabReviewStore()
    @State private var appeared = Date()
    @State private var showingKnobs = false
    @State private var showingReviews = false
    @State private var showingList = false

    /// The experiments in viewing order: the pod-shaped ones first, then
    /// the flows. Post-only experiments are reached through the stack.
    private static let order: [LabExperiment] = LabSection.allCases.flatMap { $0.bases }

    public init() {
        // The viewer is a room, not a desk: audio on, a bigger stage.
        let state = LabState()
        state.audioReactive = true
        state.showPod = false
        // Launch arguments, for screenshots from the command line:
        // `-lab.experiment frostOrb -lab.light 1`.
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: "lab.experiment"), let e = LabExperiment(rawValue: raw) { state.experiment = e }
        if defaults.bool(forKey: "lab.light") { state.darkStage = false }
        if defaults.object(forKey: "lab.mic") != nil, !defaults.bool(forKey: "lab.mic") { state.audioReactive = false }
        _lab = StateObject(wrappedValue: state)
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                (lab.darkStage ? Color(white: 0.04) : Color(white: 0.95)).ignoresSafeArea()
                pager(in: geo.size)
                    .ignoresSafeArea()

                VStack {
                    header
                    Spacer()
                    footer
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
        }
        .environment(\.colorScheme, lab.darkStage ? .dark : .light)
        .onAppear {
            appeared = Date()
            if lab.audioReactive { audio.start() }
        }
        .onChange(of: lab.audioReactive) { _, on in if on { audio.start() } else { audio.stop() } }
        .onChange(of: lab.audioAttack, initial: true) { _, v in audio.attack = v }
        .onChange(of: lab.audioRelease, initial: true) { _, v in audio.release = v }
        .sheet(isPresented: $showingKnobs) { LabKnobsSheet(lab: lab, config: config) }
        .sheet(isPresented: $showingReviews) { LabReviewsSheet(reviews: reviews, order: Self.order) }
        .sheet(isPresented: $showingList) { LabPickerSheet(lab: lab, order: Self.order) }
    }

    // MARK: - Stage

    /// Swipe between experiments on iOS; the Mac shows the current one
    /// (the Lab's own list does the picking there).
    @ViewBuilder
    private func pager(in size: CGSize) -> some View {
        #if os(iOS)
        TabView(selection: $lab.experiment) {
            ForEach(Self.order) { experiment in
                stage(for: experiment, in: size)
                    .tag(experiment)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        #else
        stage(for: lab.experiment, in: size)
        #endif
    }

    private func stage(for experiment: LabExperiment, in size: CGSize) -> some View {
        let diameter = experiment.usesPhoneCanvas
            ? size.width / 0.85 * 0.98                 // the phone canvas is 85% of `diameter`
            : min(size.width, size.height) * 0.78
        return TimelineView(.animation) { timeline in
            let frame = lab.frame(at: timeline.date, since: appeared, diameter: diameter, config: config, audio: audio)
            LabExperimentView(experiment: experiment, frame: frame, config: config, post: lab.post)
                // The flows draw their own phone; on a real phone that is
                // the screen, so scale the canvas up to fill it.
                .frame(width: size.width, height: size.height)
                .clipped()
        }
        .contentShape(Rectangle())
        .onTapGesture { if experiment.isTappable { lab.advance() } }
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in if experiment.isHoldable { lab.beginHold() } }
            .onEnded { _ in lab.endHold() })
    }

    // MARK: - Chrome

    private var header: some View {
        HStack {
            Button { showingList = true } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(lab.experiment.name).font(.headline)
                    Text(lab.experiment.technology).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Text("\(index + 1) / \(Self.order.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .modifier(LabGlassShape(cornerRadius: 18, glass: .regular))
    }

    private var index: Int { Self.order.firstIndex(of: lab.experiment) ?? 0 }

    private var footer: some View {
        VStack(spacing: 10) {
            LabStarRating(stars: reviews.binding(for: lab.experiment).stars)
            HStack(spacing: 12) {
                Button { lab.audioReactive.toggle() } label: {
                    Image(systemName: lab.audioReactive ? "mic.fill" : "mic.slash")
                        .frame(width: 22)
                }
                if lab.audioReactive {
                    LabMeter(level: min(audio.level * lab.audioSensitivity, 1))
                        .frame(width: 56)
                        .tint(config.primaryColor)
                }
                Button { lab.darkStage.toggle() } label: {
                    Image(systemName: lab.darkStage ? "moon.fill" : "sun.max.fill").frame(width: 22)
                }
                Spacer()
                Button { showingKnobs = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 22) }
                Button { showingReviews = true } label: { Image(systemName: "list.star").frame(width: 22) }
                Button { withAnimation { lab.experiment = Self.order[(index + 1) % Self.order.count] } } label: {
                    Image(systemName: "chevron.right").frame(width: 22)
                }
            }
            .font(.system(size: 17, weight: .medium))
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .modifier(LabGlassShape(cornerRadius: 22, glass: .regular))
    }
}

// MARK: - Ratings

/// One person's read on one experiment, kept on the device.
public struct LabReview: Codable, Equatable, Sendable {
    public var stars: Int = 0
    public var note: String = ""
}

/// Ratings and notes, persisted in UserDefaults as JSON — this is a
/// review tool for a handful of people, not a database.
@MainActor
public final class LabReviewStore: ObservableObject {
    @Published public private(set) var reviews: [String: LabReview] = [:]
    private let key = "nexus.lab.reviews"

    public init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: LabReview].self, from: data) {
            reviews = decoded
        }
    }

    public func review(for e: LabExperiment) -> LabReview { reviews[e.id] ?? LabReview() }

    public func set(_ review: LabReview, for e: LabExperiment) {
        reviews[e.id] = review
        if let data = try? JSONEncoder().encode(reviews) { UserDefaults.standard.set(data, forKey: key) }
    }

    func binding(for e: LabExperiment) -> Binding<LabReview> {
        Binding(get: { self.review(for: e) }, set: { self.set($0, for: e) })
    }

    /// The whole set as text, best first, for pasting into a thread.
    public func summary(order: [LabExperiment]) -> String {
        let rated = order.filter { review(for: $0).stars > 0 }.sorted { review(for: $0).stars > review(for: $1).stars }
        guard !rated.isEmpty else { return "No ratings yet." }
        return rated.map { e in
            let r = review(for: e)
            let stars = String(repeating: "★", count: r.stars) + String(repeating: "☆", count: 5 - r.stars)
            return r.note.isEmpty ? "\(stars) \(e.name)" : "\(stars) \(e.name) — \(r.note)"
        }.joined(separator: "\n")
    }
}

extension Binding where Value == LabReview {
    var stars: Binding<Int> {
        Binding<Int>(get: { self.wrappedValue.stars }, set: { self.wrappedValue.stars = $0 })
    }
    var note: Binding<String> {
        Binding<String>(get: { self.wrappedValue.note }, set: { self.wrappedValue.note = $0 })
    }
}

struct LabStarRating: View {
    @Binding var stars: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= stars ? "star.fill" : "star")
                    .font(.system(size: 20))
                    .foregroundStyle(i <= stars ? Color.yellow : Color.secondary)
                    .onTapGesture { stars = (stars == i) ? 0 : i }
            }
        }
        .accessibilityLabel("Rating")
        .accessibilityValue("\(stars) of 5")
    }
}

// MARK: - Sheets

/// The knobs for the current experiment, plus the shared few that
/// matter in a room: intensity, speed, palette, hero, post effects,
/// glyph, audio source. Same declarations the Mac panel builds from.
struct LabKnobsSheet: View {
    @ObservedObject var lab: LabState
    @ObservedObject var config: RingConfig
    @StateObject private var presets = LabPresetStore()
    @State private var saving = false
    @State private var name = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(lab.experiment.parameters) { p in
                        LabKnob(parameter: p, value: lab.binding(p, of: lab.experiment))
                    }
                    Button("Reset") { lab.resetParameters(of: lab.experiment) }
                } header: {
                    HStack {
                        Text(lab.experiment.name)
                        Spacer()
                        LabPresetsMenu(presets: presets, lab: lab, saving: $saving, name: $name)
                    }
                }
                Section("Stage") {
                    LabSlider(title: "Intensity", value: $lab.intensity, range: 0...1)
                    LabSlider(title: "Speed", value: $lab.speed, range: 0.1...3, format: "%.1f×")
                    LabSlider(title: "Fill", value: $lab.fill, range: 0...1.3)
                    Picker("Palette", selection: $lab.palette) {
                        ForEach(LabPalette.allCases) { Text($0.label).tag($0) }
                    }
                    LabSlider(title: "Hue Drift", value: $lab.hueDrift, range: -90...90, format: "%.0f°/s")
                    TextField("Glyph (SF Symbol)", text: $lab.glyph)
                    if lab.experiment.drawsHero {
                        Picker("Hero", selection: $lab.hero) {
                            Text("Ring").tag(LabExperiment?.none)
                            ForEach(LabExperiment.allCases.filter(\.canBeHero)) { e in Text(e.name).tag(LabExperiment?.some(e)) }
                        }
                    }
                }
                Section("Audio") {
                    Picker("Drives", selection: $lab.audioSource) {
                        ForEach(LabAudioSource.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    LabSlider(title: "Sensitivity", value: $lab.audioSensitivity, range: 0.5...5, format: "%.1f×")
                    LabSlider(title: "Release", value: $lab.audioRelease, range: 0.05...2, format: "%.2f s")
                }
                Section("Post Effects") {
                    ForEach(LabPostEffect.allCases) { effect in
                        Toggle(effect.experiment.name, isOn: Binding(
                            get: { lab.post.contains(effect) }, set: { _ in lab.togglePost(effect) }))
                    }
                    ForEach(lab.post, id: \.self) { effect in
                        DisclosureGroup(effect.experiment.name + " knobs") {
                            ForEach(effect.experiment.parameters) { p in
                                LabKnob(parameter: p, value: lab.binding(p, of: effect.experiment))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Knobs")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert("Save Preset", isPresented: $saving) {
                TextField("Name", text: $name)
                Button("Save") { if !name.isEmpty { presets.save(name, from: lab); name = "" } }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

struct LabReviewsSheet: View {
    @ObservedObject var reviews: LabReviewStore
    let order: [LabExperiment]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(order) { e in
                    let r = reviews.binding(for: e)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(e.name).font(.headline)
                            Spacer()
                            LabStarRating(stars: r.stars)
                        }
                        TextField("Note", text: r.note, axis: .vertical)
                            .font(.callout)
                            .lineLimit(1...3)
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("Ratings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: reviews.summary(order: order)) { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
    }
}

struct LabPickerSheet: View {
    @ObservedObject var lab: LabState
    let order: [LabExperiment]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(LabSection.allCases) { section in
                    Section {
                        ForEach(section.bases) { e in
                            Button {
                                lab.experiment = e
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: e.symbol).frame(width: 24).foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(e.name)
                                        Text(e.technology).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if e == lab.experiment { Image(systemName: "checkmark").foregroundStyle(.tint) }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Label(section.title, systemImage: section.symbol)
                    } footer: {
                        Text(section.caption)
                    }
                }
            }
            .navigationTitle("Experiments")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
