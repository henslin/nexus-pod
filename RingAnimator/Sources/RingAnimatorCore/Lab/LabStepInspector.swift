import SwiftUI

// The step inspector: one step of the flow, every setting it has, in the
// rail. Select a step in the navigator and this is the right panel —
// Keynote's model: the slide is on the canvas, its inspector beside it.
// The kit's look for the step's state shows here too, with a way to the
// bench, so "make Listening look different" is one click from the step
// where you noticed it.

struct LabStepInspector: View {
    @ObservedObject var lab: LabState
    @ObservedObject var config: RingConfig
    let step: LabStep
    /// A live frame for the look's thumbnail.
    let frameAt: (Date) -> LabFrame
    @StateObject private var clock = LabThumbClock()
    @StateObject private var presets = LabPresetStore()
    @State private var editingSurface = false
    #if os(macOS)
    @Environment(\.controlActiveState) private var activeState
    #endif

    private var index: Int { lab.flow.index(of: step.id) ?? 0 }
    private var kit: LabSpec { lab.spec }

    /// A binding into this step, wherever it is in the flow.
    private func field<T>(_ path: WritableKeyPath<LabStep, T>) -> Binding<T> {
        Binding(
            get: { (lab.flow.steps.first { $0.id == step.id } ?? step)[keyPath: path] },
            set: { v in if let i = lab.flow.index(of: step.id) { lab.flow.steps[i][keyPath: path] = v } })
    }

    var body: some View {
        #if os(macOS)
        let live = activeState != .inactive
        #else
        let live = true
        #endif
        let kind = step.kind
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            LabRailSection("q.step.showing", "Showing", summary: showingSummary) { showing }
            if step.phase == .surface {
                LabRailSection("q.step.container", "Container", summary: containerSummary) { container }
                LabRailSection("q.step.agent", "Agent", summary: step.look?.title ?? "Kit’s · \(kit.resolvedLook(for: step.verb)?.title ?? "the ring")") { agent }
                if kind.speaks {
                    LabRailSection("q.step.says", "Says", summary: step.line.isEmpty ? "Nothing" : "“\(step.line)”") { says }
                }
            }
            LabRailSection("q.step.timing", "Timing", summary: "\(step.advance.label) · \(seconds(step.seconds))") { timing }
        }
        .onAppear { clock.frameAt = frameAt; clock.run(live) }
        .onChange(of: live) { _, l in clock.run(l) }
        .onDisappear { clock.run(false) }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Step \(index + 1) of \(lab.flow.steps.count)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Duplicate") {
                    let id = lab.flow.addStep(after: step.id)
                    if let s = lab.flow.steps.first(where: { $0.id == id }) { lab.go(to: s) }
                }
                Button("Delete", role: .destructive) {
                    let before = lab.flow.steps.indices.contains(index - 1) ? lab.flow.steps[index - 1] : nil
                    lab.flow.remove(step.id)
                    if let before { lab.go(to: before) } else { lab.qSelection = .flow }
                }
                .disabled(lab.flow.steps.count <= 1)
            }
            .font(.caption)
            .buttonStyle(.borderless)
            HStack(spacing: 8) {
                Image(systemName: step.symbol).foregroundStyle(.secondary)
                // The type: what this step is for. It's the phase and the
                // state named together; changing it brings the type's
                // defaults where the step has nothing of its own.
                Picker("", selection: field(\.kind)) {
                    ForEach(LabStepKind.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu)
                .font(.headline)
                .fixedSize()
                .help(step.kind.caption)
            }
            Text(step.kind.caption)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
    }

    // MARK: Showing

    private var showingSummary: String {
        var parts = [step.tabCase.label, step.phase.label]
        if step.phase == .surface { parts.append((step.item ?? .talk).label) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var showing: some View {
        labelled("Screen") {
            Picker("", selection: field(\.tab)) {
                ForEach(NexusTab.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .labelsHidden().pickerStyle(.menu).controlSize(.small)
        }
        if step.phase == .surface {
            labelled("Action") {
                Picker("", selection: Binding(get: { step.item ?? .talk }, set: { field(\.item).wrappedValue = $0 })) {
                    ForEach(kit.items) { Text($0.label).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).controlSize(.small)
            }
            .help("Which action opened this container — the kit says what each one opens.")
        }
    }

    // MARK: Container

    private var item: LabActionItem { step.item ?? .talk }
    private var kitSurface: LabSurfaceSpec { kit.resolvedSurface(for: item) }
    private var containerSummary: String {
        if let s = step.surface { return "This step’s · \(s.kind.label)" + (s.adornments.isEmpty ? "" : " · " + s.adornments.map(\.label).joined(separator: ", ")) }
        return "Kit’s · \(kitSurface.kind.label)"
    }
    /// The step's own surface, starting from the kit's the moment it's
    /// touched.
    private var surfaceBinding: Binding<LabSurfaceSpec> {
        Binding(get: { step.surface ?? kitSurface }, set: { field(\.surface).wrappedValue = $0 })
    }

    @ViewBuilder private var container: some View {
        labelled("Uses") {
            Picker("", selection: Binding(get: { step.surface != nil }, set: { own in field(\.surface).wrappedValue = own ? kitSurface : nil })) {
                Text("Kit’s").tag(false)
                Text("This step’s").tag(true)
            }
            .labelsHidden().pickerStyle(.segmented).controlSize(.small)
        }
        .help("The kit's container for \(item.label), or one this step insists on — its own kind, adornments, transitions and morph knobs. Starts as a copy of the kit's.")
        if step.surface != nil {
            let surface = surfaceBinding
            labelled("Kind") {
                Picker("", selection: Binding(get: { surface.wrappedValue.kind }, set: { surface.wrappedValue.kind = $0 })) {
                    ForEach(LabMorphKind.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).controlSize(.small)
            }
            labelled("Carries") {
                Menu {
                    ForEach(LabMorphAdornment.allCases) { a in
                        let on = surface.wrappedValue.adornments.contains(a)
                        Button {
                            var v = surface.wrappedValue
                            if on { v.adornments.removeAll { $0 == a } } else { v.adornments.append(a) }
                            surface.wrappedValue = v
                        } label: { Label(a.label, systemImage: on ? "checkmark" : a.symbol) }
                    }
                } label: {
                    Text(surface.wrappedValue.adornments.isEmpty ? "Nothing" : surface.wrappedValue.adornments.map(\.label).joined(separator: ", "))
                        .font(.callout).lineLimit(1)
                        .foregroundStyle(surface.wrappedValue.adornments.isEmpty ? .tertiary : .primary)
                }
                .menuStyle(.borderlessButton).controlSize(.small)
            }
            .help("Edge glow, waveform, caption, transcript, border beam — what rides on the container at this step.")
            labelled("In · Out") {
                Picker("", selection: Binding(get: { surface.wrappedValue.enter }, set: { surface.wrappedValue.enter = $0 })) {
                    ForEach(LabMorphTransition.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).controlSize(.small)
                Picker("", selection: Binding(get: { surface.wrappedValue.exit }, set: { surface.wrappedValue.exit = $0 })) {
                    ForEach(LabMorphTransition.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).controlSize(.small)
            }
            HStack {
                Button { editingSurface = true } label: { Label("Tune the Container…", systemImage: "slider.horizontal.3") }
                    .controlSize(.small)
                    .popover(isPresented: $editingSurface, arrowEdge: .leading) {
                        LabContainerEditor(item: item, surface: surface, frameAt: frameAt, config: config)
                    }
                    .help("Backdrop, hero size, dim, and every knob of the morph and its adornments — for this step only.")
                Spacer()
                Button("Back to Kit’s") { field(\.surface).wrappedValue = nil }
                    .controlSize(.small)
            }
        }
    }

    // MARK: Agent

    /// The look the agent wears here: the kit's for the state, or this
    /// step's own. The step's row is a slot like the kit's — gallery,
    /// tune in place, the bench — and Use from the bench lands here, not
    /// in the kit. Clear it and the step wears the kit's again.
    @ViewBuilder private var agent: some View {
        labelled("Wears") {
            Picker("", selection: Binding(get: { step.look != nil }, set: { own in
                field(\.look).wrappedValue = own ? (kit.resolvedLook(for: step.verb) ?? LabLook(experiment: LabExperiment.orbKit.id)) : nil
            })) {
                Text("Kit’s").tag(false)
                Text("This step’s").tag(true)
            }
            .labelsHidden().pickerStyle(.segmented).controlSize(.small)
        }
        .help("The kit's look for \(step.verb.label), or a look of this step's own — starting as a copy of the kit's, then dialled in here.")
        if step.look != nil {
            LabSlotRow(lab: lab, config: config, clock: clock, frameAt: frameAt, title: "Look", symbol: step.verb.symbol,
                       look: step.look, target: .step(step.id), set: { field(\.look).wrappedValue = $0 }, presets: presets)
        } else {
            let look = kit.look(for: step.verb)
            LabSlotRow(lab: lab, config: config, clock: clock, frameAt: frameAt, title: step.verb.label, symbol: step.verb.symbol,
                       look: look, target: .state(step.verb), set: { lab.spec.states[step.verb.rawValue] = $0 }, presets: presets)
            Text("Editing here changes \(step.verb.label) in the kit — every step that wears it.")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    // MARK: Says

    private var linePrompt: String {
        switch step.verb {
        case .listening: return "What the person asks"
        case .searching: return "The named work — “Checking the doorbell…”"
        case .speaking: return "The agent’s answer"
        case .done: return "Follow-ups, one per line"
        case .error: return "What went wrong"
        default: return "Nothing is said here"
        }
    }

    @ViewBuilder private var says: some View {
        TextField(linePrompt, text: field(\.line), axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .lineLimit(1...5)
            .disabled(!step.speaks)
            .help(linePrompt)
        if step.kind.carries {
            labelled("Carries") {
                Picker("", selection: Binding(get: { step.carries }, set: { field(\.carries).wrappedValue = $0 })) {
                    Text("Nothing").tag(QuidgetKind?.none)
                    Divider()
                    ForEach(kit.quidgetKinds) { Label($0.label, systemImage: $0.symbol).tag(QuidgetKind?.some($0)) }
                }
                .labelsHidden().pickerStyle(.menu).controlSize(.small)
            }
            .help("A quick widget the reply carries — the thing asked about, as a control.")
        }
        if step.kind.acts {
            labelled("Does") {
                Picker("", selection: Binding(get: { effectChoice }, set: { setEffect($0) })) {
                    Text("Nothing").tag("none")
                    Divider()
                    ForEach(SecurityMode.allCases) { Text("Arm · \($0.label)").tag("arm.\($0.rawValue)") }
                    Divider()
                    Text("Dim the light").tag("dim")
                }
                .labelsHidden().pickerStyle(.menu).controlSize(.small)
            }
            .help("The agent's hand on the house as this step is reached — the dashboard arms, the light dims.")
            if case .dim(let level) = step.effect {
                labelled("To") {
                    Slider(value: Binding(get: { level }, set: { field(\.effect).wrappedValue = .dim($0) }), in: 0...1)
                        .controlSize(.small)
                    Text("\(Int((level * 100).rounded()))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                }
            }
        }
    }

    private var effectChoice: String {
        switch step.effect {
        case .none: return "none"
        case .arm(let m): return "arm.\(m.rawValue)"
        case .dim: return "dim"
        }
    }
    private func setEffect(_ choice: String) {
        if choice == "none" { field(\.effect).wrappedValue = nil }
        else if choice == "dim" { field(\.effect).wrappedValue = .dim(0.4) }
        else if let m = SecurityMode(rawValue: String(choice.dropFirst(4))) { field(\.effect).wrappedValue = .arm(m) }
    }

    // MARK: Timing

    private func seconds(_ s: Double) -> String { String(format: s == s.rounded() ? "%.0f s" : "%.1f s", s) }

    @ViewBuilder private var timing: some View {
        labelled("Advances") {
            Picker("", selection: field(\.advance)) {
                ForEach(LabStepAdvance.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden().pickerStyle(.segmented).controlSize(.small)
        }
        .help("Timer: the clock moves on after the seconds below. Tap and Hold: in Interact, what the person does here; on the clock they play as timers.")
        labelled("Holds") {
            Slider(value: field(\.seconds), in: 0.5...10, step: 0.5)
                .controlSize(.small)
            Text(seconds(step.seconds)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
        }
    }

    /// Label · control, on the rail's grid.
    private func labelled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.callout).foregroundStyle(.secondary)
                .frame(width: LabRailMetrics.labelWidth, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }
}
