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
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            LabRailSection("q.step.showing", "Showing", summary: showingSummary) { showing }
            if step.phase == .surface {
                LabRailSection("q.step.agent", "Agent", summary: step.verb.label) { agent }
                LabRailSection("q.step.says", "Says", summary: step.line.isEmpty ? "Nothing" : "“\(step.line)”") { says }
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
                Text(step.title).font(.headline)
            }
        }
        .padding(14)
    }

    // MARK: Showing

    private var showingSummary: String {
        var parts = [step.tabCase.label, step.phase.label]
        if step.phase == .surface { parts.append((step.item ?? .talk).label) }
        if let c = step.container { parts.append(c.label) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var showing: some View {
        labelled("Screen") {
            Picker("", selection: field(\.tab)) {
                ForEach(NexusTab.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .labelsHidden().pickerStyle(.menu).controlSize(.small)
        }
        labelled("Showing") {
            Picker("", selection: field(\.phase)) {
                ForEach(LabStepPhase.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden().pickerStyle(.menu).controlSize(.small)
        }
        .help("The pod at rest; its menu open; an action's container with the agent in a state; the app-wide Ask button on another screen; that button's menu.")
        if step.phase == .surface {
            labelled("Action") {
                Picker("", selection: Binding(get: { step.item ?? .talk }, set: { field(\.item).wrappedValue = $0 })) {
                    ForEach(kit.items) { Text($0.label).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).controlSize(.small)
            }
            .help("Which action opened this container — the kit says what each one opens.")
            labelled("Container") {
                Picker("", selection: Binding(get: { step.container }, set: { field(\.container).wrappedValue = $0 })) {
                    Text("Kit’s · \(kit.resolvedSurface(for: step.item ?? .talk).kind.label)").tag(LabMorphKind?.none)
                    Divider()
                    ForEach(LabMorphKind.allCases) { Text($0.label).tag(LabMorphKind?.some($0)) }
                }
                .labelsHidden().pickerStyle(.menu).controlSize(.small)
            }
            .help("The kit's container for this action, or one this step insists on.")
        }
    }

    // MARK: Agent

    @ViewBuilder private var agent: some View {
        labelled("State") {
            Picker("", selection: field(\.verb)) {
                ForEach(LabAgentVerb.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
            }
            .labelsHidden().pickerStyle(.menu).controlSize(.small)
        }
        let look = kit.look(for: step.verb)
        HStack(spacing: 10) {
            Group {
                if let l = kit.resolvedLook(for: step.verb) {
                    LabLiveThumb(clock: clock, look: l, config: config, size: 36)
                } else {
                    Circle().fill(.quaternary)
                }
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(look?.title ?? "The pod’s look")
                    .font(.callout)
                Text(step.verb.caption)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button(look == nil ? "Choose" : "Edit") { lab.edit(look, for: .state(step.verb)) }
                .controlSize(.small)
                .help(look == nil ? "Choose a look for \(step.verb.label) in the Lab; Use puts it in the kit." : "Tune \(step.verb.label)'s look on the bench; Use puts it back.")
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
        if step.verb == .speaking || step.verb == .done {
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
        if step.verb == .speaking || step.verb == .listening {
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
