import SwiftUI

// The System room: the spec played on a phone, and the board of slots
// beside it. See `LabSpec.swift` for the model and the why.

// MARK: - Play

/// The spec, end to end, on a phone: the pod at rest → a tap opens the
/// menu → an action opens its surface → a real conversation runs
/// through the states (the ask, thinking, the named work, the answer
/// arriving, the follow-ups) → back to the pod. Then the app-wide Ask
/// button on another screen, and its menu. Every piece is what the
/// board assigned; an empty slot plays as the ring or the default
/// surface, so a gap is visible rather than fatal. A hold goes straight
/// to the long-press action, listening while held and speaking after.
public struct LabPlayView: View {
    let frame: LabFrame
    @ObservedObject var config: RingConfig

    public init(frame: LabFrame, config: RingConfig) {
        self.frame = frame
        self.config = config
    }

    enum Step: Equatable {
        case idle, menu
        case surface(LabActionItem, LabAgentVerb)
        /// The Ask button on a screen that isn't the Nexus tab.
        case askAnywhere
        case askMenu
    }

    /// The tap-driven sequence this spec plays.
    static func steps(of spec: LabSpec) -> [Step] {
        var steps: [Step] = [.idle]
        let item: LabActionItem? = spec.tap.item ?? (spec.tap == .menu ? (spec.items.contains(.talk) ? .talk : spec.items.first) : nil)
        if spec.tap == .menu { steps.append(.menu) }
        if let item {
            for verb in [LabAgentVerb.listening, .thinking, .searching, .speaking, .done] { steps.append(.surface(item, verb)) }
        }
        steps.append(.askAnywhere)
        steps.append(.askMenu)
        return steps
    }

    /// For harnesses: how many steps the spec plays.
    public static func stepCount(of spec: LabSpec) -> Int { steps(of: spec).count }

    static func title(of step: Step) -> String {
        switch step {
        case .idle: return "Idle"
        case .menu: return "Menu"
        case .surface(let item, let verb):
            let v = item == .ask && verb == .listening ? "Typing" : verb.label
            return "\(item.label) · \(v)"
        case .askAnywhere: return "Ask · Devices"
        case .askMenu: return "Ask · Menu"
        }
    }

    /// Where the play is: the step, and the clock within it. A hold
    /// overrides the sequence — the long-press action, listening while
    /// held, speaking for `talk` seconds after.
    private func situation(_ spec: LabSpec, steps: [Step], index: Int, hold: Double, auto: Bool, talk: Double) -> (step: Step, since: Double, until: Double) {
        var step = steps[index]
        var sinceChange = min(frame.sinceTap, auto ? frame.time.truncatingRemainder(dividingBy: hold) : .infinity)
        var untilChange = auto ? hold - sinceChange : .infinity
        if let held = spec.longPress.item ?? (spec.longPress == .menu ? .talk : nil) {
            if frame.holding > 0 {
                step = .surface(held, .listening); sinceChange = frame.holding; untilChange = .infinity
            } else if frame.sinceHold < talk {
                step = .surface(held, .speaking); sinceChange = frame.sinceHold; untilChange = talk - frame.sinceHold
            }
        }
        return (step, sinceChange, untilChange)
    }

    public var body: some View {
        let spec = frame.spec
        let steps = Self.steps(of: spec)
        let hold = max(frame.p("hold", .system), 0.2)
        let auto = frame.p("auto", .system) >= 0.5
        let talk = frame.p("talk", .system)
        let script = LabScript.named(Int(frame.p("script", .system)))
        let spring = Animation.spring(response: frame.p("spring", .system), dampingFraction: 1 - frame.p("bounce", .system) * 0.45)
        let index = frame.stage(of: .system, count: steps.count)
        let (step, sinceChange, untilChange) = situation(spec, steps: steps, index: index, hold: hold, auto: auto, talk: talk)
        // What the panel is: the pod, or the action's surface.
        let item: LabActionItem? = { if case .surface(let i, _) = step { return i } else { return nil } }()
        let verb: LabAgentVerb = { if case .surface(_, let v) = step { return v } else { return .idle } }()
        let surface = item.map { spec.resolvedSurface(for: $0) } ?? LabSurfaceSpec(kind: .pod)
        let state = surface.morphState
        let look = spec.resolvedLook(for: verb)
        let panelFrame = frame.applying(look, config: config).applying(surface)
        // The content's transition clock runs from when the surface
        // opened, not from each verb — the verbs change inside it.
        let firstSurface = steps.firstIndex { if case .surface = $0 { return true } else { return false } } ?? index
        let held = frame.holding > 0 || frame.sinceHold < talk
        let surfaceAge = held ? sinceChange
            : (auto && index >= firstSurface ? sinceChange + Double(index - firstSurface) * hold : sinceChange)
        let lastSurface = steps.lastIndex { if case .surface = $0 { return true } else { return false } } ?? index
        let untilClose = (auto && index == lastSurface) || frame.sinceHold < talk ? untilChange : .infinity
        let conversation = item.map { LabConversation(script: script, mode: $0 == .talk ? .voice : .text, verb: verb, since: sinceChange, age: surfaceAge) }
        let onAnotherScreen = step == .askAnywhere || step == .askMenu
        let phone = LabMorphView.phone
        let home = LabMorphView.home(of: state.kind)
        let podHome = LabMorphView.home(of: .pod)
        let placement = spec.askPlacement ?? .floating
        let askHome: CGPoint = {
            switch placement {
            case .floating: return CGPoint(x: phone.width - 16 - 26, y: phone.height - 24 - 62 - 14 - 26)
            case .navBar: return CGPoint(x: phone.width - 16 - 22, y: 62)
            case .tabBar: return podHome
            }
        }()
        let showChrome = frame.p("chrome", .system) >= 0.5

        return ZStack {
            (onAnotherScreen ? DemoTab.devices : DemoTab.dashboard).screenshotImage(dark: frame.darkStage)
                .resizable().scaledToFill()
                .frame(width: phone.width, height: phone.height)
                .clipped()
                .animation(.easeInOut(duration: 0.25), value: onAnotherScreen)
            Color.black.opacity(state.kind == .sheet ? 0.4 : state.kind == .fullScreen ? 0.85 : state.kind == .pod ? 0 : 0.15)
                .animation(spring, value: state.kind)
            VStack {
                Spacer()
                TabBarPreview(config: config, selectedTab: .constant(onAnotherScreen ? .devices : .dashboard), width: phone.width - 32, hidesPodContent: true)
                    .allowsHitTesting(false)
                    .padding(.bottom, 24)
                    .opacity(state.kind == .fullScreen ? 0 : 1)
                    .animation(spring, value: state.kind)
            }
            // The menu, out of the pod's slot. Drawn under the pod so its
            // own disc sits behind the glass.
            if spec.tap == .menu, !onAnotherScreen {
                LabGooeyMenu(frame: frame.applying(spec.action, config: config),
                             center: podHome, open: step == .menu,
                             since: step == .menu ? sinceChange : (index > 1 && auto ? sinceChange + Double(index - 2) * hold : sinceChange),
                             icons: spec.items.map(\.symbol), drawsButton: false)
                    .opacity(state.kind == .pod ? 1 : 0)
                    .animation(spring, value: state.kind)
            }
            // The Ask button, elsewhere in the app: the goo, with the
            // agent's mark on it, where the spec places it; the menu
            // comes out of it.
            if onAnotherScreen {
                let askFrame = frame.applying(spec.ask ?? spec.action, config: config).applying(spec.resolvedLook(for: .idle), config: config)
                LabAskButton(frame: askFrame, config: config, size: phone, placement: placement, style: spec.askStyle ?? .goo,
                             open: step == .askMenu, since: sinceChange, items: spec.items,
                             suggestions: LabAskContext.devices)
            }
            LabMorphPanel(state: state, frame: panelFrame, config: config,
                          sinceChange: state.kind == .pod ? .infinity : surfaceAge,
                          untilChange: untilClose,
                          caption: verb.caption,
                          conversation: conversation)
                .position(onAnotherScreen ? podHome : home)
                .animation(spring, value: state.kind)
            if showChrome {
                VStack(spacing: 3) {
                    Text(Self.title(of: step))
                        .font(.system(size: 13, weight: .semibold))
                        .contentTransition(.numericText())
                        .animation(spring, value: step)
                    Text("\(index + 1) of \(steps.count) · \(script.title)")
                        .font(.caption2)
                        .opacity(0.6)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(.black.opacity(0.4)))
                .padding(.top, 14)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(width: phone.width, height: phone.height)
        .clipShape(RoundedRectangle(cornerRadius: 50, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 50, style: .continuous).strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
    }
}

// MARK: - The stage: play, with a strip of steps

/// Q Branch's stage: the phone, and the steps under it. The board is
/// the rail (see `LabSpecBoard`), so this is only the thing being
/// played and the way to move through it.
struct LabSystemStage: View {
    @ObservedObject var lab: LabState
    @ObservedObject var config: RingConfig
    let frame: LabFrame

    var body: some View {
        let scale = frame.diameter * 1.9 / LabMorphView.phone.height
        VStack(spacing: 18) {
            LabPlayView(frame: frame, config: config)
                .scaleEffect(scale)
                .frame(width: LabMorphView.phone.width * scale, height: LabMorphView.phone.height * scale)
                .contentShape(Rectangle())
                .onTapGesture { lab.advance() }
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { _ in lab.beginHold() }
                    .onEnded { _ in lab.endHold() })
            LabPlayStrip(lab: lab, frame: frame)
        }
    }
}

/// The steps of the play as chips — click any to go there — with the
/// auto/tap switch and a restart.
struct LabPlayStrip: View {
    @ObservedObject var lab: LabState
    let frame: LabFrame

    var body: some View {
        let steps = LabPlayView.steps(of: frame.spec)
        let current = frame.stage(of: .system, count: steps.count)
        let auto = frame.p("auto", .system) >= 0.5
        VStack(spacing: 10) {
            LabWrap(spacing: 6) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    Button {
                        // Tap mode, at this step: the clock stops, taps count.
                        lab.values["system.auto"] = 0
                        lab.taps = i
                        lab.lastTap = Date()
                    } label: {
                        HStack(spacing: 4) {
                            if i > 0 { Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary) }
                            Text(LabPlayView.title(of: step))
                                .font(.caption.weight(i == current ? .semibold : .regular))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(i == current ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.fill.quaternary)))
                        .overlay(Capsule().strokeBorder(i == current ? Color.primary.opacity(0.25) : .clear))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 560)
            HStack(spacing: 14) {
                Toggle("Auto", isOn: Binding(get: { auto }, set: { lab.values["system.auto"] = $0 ? 1 : 0; lab.taps = 0 }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Button {
                    lab.taps = 0
                    lab.lastTap = Date()
                } label: { Label("Restart", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(.borderless)
                    .font(.caption)
                Text("Tap the phone to step · hold it to talk")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(frame.darkStage ? Color.white : Color.black)
    }
}

// MARK: - The board

/// Every slot the product has, with what is in it — Q Branch's rail.
/// A slot's menu is where it gets filled: from the bench as it stands,
/// from a saved preset, or by going to the Lab to choose (the rail there
/// shows the errand and a Use button). Surfaces are edited in place.
public struct LabSpecBoard: View {
    @ObservedObject var lab: LabState
    @ObservedObject var config: RingConfig
    let frame: LabFrame
    @ObservedObject var specs: LabSpecStore
    @StateObject private var presets = LabPresetStore()
    @State private var pasteFailed = false

    public init(lab: LabState, config: RingConfig, frame: LabFrame, specs: LabSpecStore) {
        self.lab = lab
        self.config = config
        self.frame = frame
        self.specs = specs
    }

    private var spec: LabSpec { lab.spec }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 12)
            group("Pod", "At rest, in the tab bar.") {
                slot(title: "Pod", look: spec.pod, target: .pod, set: { lab.spec.pod = $0 })
            }
            group("Agent States", "One look per verb. Their orb wears its nearest verb; any orb can take any state.", trailing: {
                Menu {
                    Button("Their Orb, Their Verbs") { lab.useOrbKitForEveryState() }
                    if let bench = lab.lastBench, bench.canBeHero {
                        Button("\(bench.name), Every State") {
                            let look = LabLook(from: lab, experiment: bench)
                            for v in LabAgentVerb.allCases { lab.spec.states[v.rawValue] = look }
                        }
                    }
                    Button("Clear All", role: .destructive) { lab.spec.states = [:] }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }) {
                LabWrap(spacing: 8) {
                    ForEach(LabAgentVerb.allCases) { verb in
                        slot(title: verb.label, look: spec.look(for: verb), target: .state(verb), set: { lab.spec.states[verb.rawValue] = $0 })
                    }
                }
            }
            group("Ask", "The Ask button — everywhere in the app, not only the tab. What it looks like, where it sits, what it reveals.") {
                HStack(alignment: .top, spacing: 14) {
                    slot(title: "Button", look: spec.ask, target: .ask, set: { lab.spec.ask = $0 }, menu: true)
                    slot(title: "Menu", look: spec.action, target: .action, set: { lab.spec.action = $0 }, menu: true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Placement").font(.caption.weight(.semibold))
                        Picker("", selection: Binding(get: { lab.spec.askPlacement ?? .floating }, set: { lab.spec.askPlacement = $0 })) {
                            ForEach(LabAskPlacement.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        Text("Style").font(.caption.weight(.semibold))
                        LabChips(choices: LabAskStyle.allCases.map(\.label),
                                 selection: Binding(get: { LabAskStyle.allCases.firstIndex(of: lab.spec.askStyle ?? .goo) ?? 0 },
                                                    set: { lab.spec.askStyle = LabAskStyle.allCases[$0] }))
                    }
                }
                Text("Items").font(.caption.weight(.semibold))
                LabWrap(spacing: 6) {
                    ForEach(LabActionItem.allCases) { item in
                        let on = spec.items.contains(item)
                        Button { lab.toggleItem(item) } label: {
                            Label(item.label, systemImage: item.symbol)
                                .font(.caption)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(on ? Color.accentColor.opacity(0.25) : Color.clear))
                                .overlay(Capsule().strokeBorder(on ? Color.accentColor : Color.secondary.opacity(0.4)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            group("Surfaces", "What each item opens. Edit in place, or send a Morph state here from its card.") {
                ForEach(spec.items) { item in
                    surfaceEditor(item)
                }
            }
            group("Gestures", "The two touches on the pod.") {
                Picker("Tap", selection: Binding(get: { lab.spec.tap }, set: { lab.spec.tap = $0 })) {
                    ForEach(LabGestureResult.allCases) { Text($0.label).tag($0) }
                }
                Picker("Long press", selection: Binding(get: { lab.spec.longPress }, set: { lab.spec.longPress = $0 })) {
                    ForEach(LabGestureResult.allCases) { Text($0.label).tag($0) }
                }
            }
            group("Play", "How the stage steps through it.") {
                LabKnobList(lab: lab, experiment: .system)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TextField("Spec name", text: Binding(get: { lab.spec.name }, set: { lab.spec.name = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .font(.title3.weight(.semibold))
                specsMenu
            }
            HStack {
                Text("\(spec.filled) of \(spec.total) slots filled")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Copy JSON") { LabSpecStore.copy(spec) }
                    .font(.caption)
                Button("Paste") {
                    if let s = LabSpecStore.paste() { lab.spec = s; pasteFailed = false } else { pasteFailed = true }
                }
                .font(.caption)
            }
            .buttonStyle(.borderless)
            if pasteFailed {
                Text("The pasteboard doesn't hold a spec.").font(.caption2).foregroundStyle(.red)
            }
            Text("Click a slot to fill it — from the bench, a preset, or the Lab. Copy JSON, then Paste Spec in Nexus Lab to play it on the phone.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var specsMenu: some View {
        Menu {
            if specs.specs.isEmpty {
                Text("No saved specs")
            } else {
                Section("Load") {
                    ForEach(specs.specs) { s in Button(s.name) { lab.spec = s } }
                }
                Menu("Delete") {
                    ForEach(specs.specs) { s in Button(s.name, role: .destructive) { specs.delete(s) } }
                }
            }
            Section("Starters") {
                ForEach(LabSpec.starters) { s in Button(s.name) { lab.spec = s } }
            }
            Divider()
            Button("Save “\(spec.name)”") { specs.save(spec) }
            Button("Save a Copy") { var s = spec; s.id = UUID(); s.name += " copy"; specs.save(s); lab.spec = s }
            Button("New Spec", role: .destructive) { lab.spec = LabSpec() }
        } label: {
            Label("Specs", systemImage: "square.stack")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func group<Content: View, Trailing: View>(_ title: String, _ caption: String,
                                                      @ViewBuilder trailing: () -> Trailing = { EmptyView() },
                                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                trailing()
            }
            Text(caption).font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            content()
        }
        .padding(.bottom, 20)
    }

    // MARK: Slots

    /// One orb slot: the look at pod size in the pod's glass, or a gap —
    /// and, as its menu, every way to fill it.
    private func slot(title: String, look: LabLook?, target: LabSlotTarget, set: @escaping (LabLook?) -> Void, menu: Bool = false) -> some View {
        VStack(spacing: 6) {
            Menu {
                Button {
                    lab.choose(for: target)
                } label: { Label("Choose in the Lab…", systemImage: "flask") }
                if let bench = lab.lastBench, target.accepts(bench) {
                    Button("Use the Bench · \(bench.name)") { set(LabLook(from: lab, experiment: bench)) }
                }
                let mine = presets.presets.filter { p in LabExperiment(rawValue: p.experiment).map(target.accepts) ?? false }
                if !mine.isEmpty {
                    Menu("From a Preset") {
                        ForEach(mine) { p in
                            Button("\(LabExperiment(rawValue: p.experiment)?.name ?? p.experiment) · \(p.name)") {
                                set(LabLook(experiment: p.experiment, values: p.values, post: p.post, palette: p.palette))
                            }
                        }
                    }
                }
                if let look {
                    Divider()
                    Button("Open in Lab") { lab.open(look) }
                    Button("Clear", role: .destructive) { set(nil) }
                }
            } label: {
                ZStack {
                    if let look, menu {
                        // The menu's button, in the goo's fill.
                        let fillChoice = Int(look.values["gooey.fill"] ?? 1)
                        let fill: Color = [Color(white: 0.13), Color(white: 0.92), Color(hex: "#5AC8FA"), Color(hex: "#FFCF9E"), frame.colors.first ?? .white][min(max(fillChoice, 0), 4)]
                        Circle().fill(fill).frame(width: 52, height: 52)
                        Image(systemName: "plus").font(.system(size: 22, weight: .semibold)).foregroundStyle(fillChoice == 0 ? .white : Color(white: 0.1))
                    } else if let look {
                        LabPodGlass(config: config, dark: frame.darkStage) {
                            LabHeroView(frame: frame.applying(look, config: config), config: config, diameter: 62)
                        }
                    } else {
                        Circle()
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(.tertiary)
                            .frame(width: 62, height: 62)
                        Image(systemName: "plus").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 62, height: 62)
                .contentShape(Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            Text(title).font(.caption.weight(.semibold))
            Text(look.map { $0.experimentCase == .gooey ? gooeyEffectName($0) : $0.title } ?? "Empty")
                .font(.caption2)
                .foregroundStyle(look == nil ? .tertiary : .secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 92)
        }
        .frame(width: 96)
    }

    private func gooeyEffectName(_ look: LabLook) -> String {
        let choices = LabExperiment.gooey.parameters.first { $0.id == "effect" }?.choices ?? []
        let i = Int(look.values["gooey.effect"] ?? 0)
        return choices.indices.contains(i) ? "Gooey · \(choices[i])" : "Gooey"
    }

    /// One surface, edited in place: its shape, what it carries, how it
    /// comes and goes — with the panel beside, small.
    private func surfaceEditor(_ item: LabActionItem) -> some View {
        let assigned = spec.surface(for: item)
        let surface = spec.resolvedSurface(for: item)
        let real = LabMorphPanel.size(of: surface.kind)
        let box: CGFloat = 96
        let scale = min(box / real.width, box / real.height, 1)
        let look = spec.resolvedLook(for: .listening)
        func update(_ change: (inout LabSurfaceSpec) -> Void) {
            var s = surface
            change(&s)
            lab.spec.surfaces[item.rawValue] = s
        }
        return HStack(alignment: .top, spacing: 12) {
            LabMorphPanel(state: surface.morphState, frame: frame.applying(look, config: config).applying(surface), config: config, caption: LabAgentVerb.listening.caption)
                .scaleEffect(scale)
                .frame(width: box, height: box)
                .opacity(assigned == nil ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(item.label, systemImage: item.symbol).font(.caption.weight(.semibold))
                    if assigned == nil { Text("default").font(.caption2).foregroundStyle(.tertiary) }
                    Spacer()
                    if assigned != nil {
                        Menu {
                            Button("Open in Morph") { lab.open(surface) }
                            Button("Reset to Default", role: .destructive) { lab.spec.surfaces[item.rawValue] = nil }
                        } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    }
                }
                LabChips(choices: LabMorphKind.allCases.map(\.label),
                         selection: Binding(get: { LabMorphKind.allCases.firstIndex(of: surface.kind) ?? 0 },
                                            set: { i in update { $0.kind = LabMorphKind.allCases[i] } }))
                    .controlSize(.small)
                LabWrap(spacing: 4) {
                    ForEach(LabMorphAdornment.allCases) { a in
                        let on = surface.adornments.contains(a)
                        Button {
                            update { s in if on { s.adornments.removeAll { $0 == a } } else { s.adornments.append(a) } }
                        } label: {
                            Label(a.label, systemImage: a.symbol)
                                .font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(Capsule().fill(on ? Color.accentColor.opacity(0.25) : Color.clear))
                                .overlay(Capsule().strokeBorder(on ? Color.accentColor : Color.secondary.opacity(0.4)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: 8) {
                    Picker("In", selection: Binding(get: { surface.enter }, set: { v in update { $0.enter = v } })) {
                        ForEach(LabMorphTransition.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Out", selection: Binding(get: { surface.exit }, set: { v in update { $0.exit = v } })) {
                        ForEach(LabMorphTransition.allCases.filter { $0 != .flare }) { Text($0.label).tag($0) }
                    }
                }
                .font(.caption)
                .controlSize(.small)
            }
        }
        .padding(.bottom, 6)
    }
}

/// A 62pt pod in Liquid Glass — the tab bar's, for thumbnails.
struct LabPodGlass<Content: View>: View {
    @ObservedObject var config: RingConfig
    let dark: Bool
    @ViewBuilder let content: () -> Content
    @Environment(\.labNoGlass) private var noGlass

    var body: some View {
        let inner = content()
            .frame(width: 62, height: 62)
            .clipShape(Circle())
        Group {
            if noGlass {
                inner.background(Color.black.opacity(0.5), in: Circle())
            } else if #available(iOS 26.0, macOS 26.0, *) {
                inner.glassEffect(config.glass, in: Circle())
            } else {
                inner.background(.ultraThinMaterial, in: Circle())
            }
        }
        .environment(\.colorScheme, dark ? .dark : .light)
    }
}

// MARK: - Use as…

/// The one gesture that fills a slot: the current experiment, as tuned,
/// into the pod, a state, or the menu. Lives in the rail beside the
/// experiment's name.
struct LabUseAsMenu: View {
    @ObservedObject var lab: LabState

    var body: some View {
        let e = lab.experiment
        Menu {
            if e.canBeHero {
                Button { lab.useCurrentLookAsPod() } label: { Label("Pod", systemImage: "circle.fill") }
                Section("State") {
                    ForEach(LabAgentVerb.allCases) { verb in
                        Button { lab.useCurrentLook(for: verb) } label: { Label(verb.label, systemImage: verb.symbol) }
                    }
                }
                if e == .orbKit {
                    Divider()
                    Button("Every State, Their Verbs") { lab.useOrbKitForEveryState() }
                }
            }
            if e == .gooey {
                Button { lab.useCurrentGooeyAsAction() } label: { Label("Pod Menu", systemImage: "plus.circle.fill") }
                Button { lab.useCurrentAskButton() } label: { Label("Ask Button", systemImage: "sparkles") }
            }
            if e == .askButton {
                Button { lab.useCurrentAskButton() } label: { Label("Ask Button", systemImage: "sparkles") }
            }
            if e == .morph {
                Text("Use a state's own menu, on its card below.")
            }
        } label: {
            Label("Use as…", systemImage: "arrow.down.right.square")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
