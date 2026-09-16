import SwiftUI

// The System room: the spec played on a phone, and the board of slots
// beside it. See `LabSpec.swift` for the model and the why.

// MARK: - Play

/// The spec, end to end, on a phone: the pod at rest → a tap opens the
/// menu → an action opens its surface → the agent listens, thinks,
/// searches, speaks, finishes → back to the pod. Every piece is what the
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
        var kind: LabMorphKind? { if case .surface(let item, _) = self { return item.defaultSurface } else { return nil } }
    }

    /// The tap-driven sequence this spec plays.
    static func steps(of spec: LabSpec) -> [Step] {
        var steps: [Step] = [.idle]
        let item: LabActionItem? = spec.tap.item ?? (spec.tap == .menu ? (spec.items.contains(.talk) ? .talk : spec.items.first) : nil)
        if spec.tap == .menu { steps.append(.menu) }
        if let item {
            for verb in [LabAgentVerb.listening, .thinking, .searching, .speaking, .done] { steps.append(.surface(item, verb)) }
        }
        return steps
    }

    static func title(of step: Step) -> String {
        switch step {
        case .idle: return "Idle"
        case .menu: return "Menu"
        case .surface(let item, let verb): return "\(item.label) · \(verb.label)"
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
        let surfaceAge = (frame.holding > 0 || frame.sinceHold < talk) ? sinceChange
            : (auto && index >= firstSurface ? sinceChange + Double(index - firstSurface) * hold : sinceChange)
        let untilClose = (auto && index == steps.count - 1) || frame.sinceHold < talk ? untilChange : .infinity
        let phone = LabMorphView.phone
        let home = LabMorphView.home(of: state.kind)
        let podHome = LabMorphView.home(of: .pod)
        let showChrome = frame.p("chrome", .system) >= 0.5

        return ZStack {
            DemoTab.dashboard.screenshotImage(dark: frame.darkStage)
                .resizable().scaledToFill()
                .frame(width: phone.width, height: phone.height)
                .clipped()
            Color.black.opacity(state.kind == .sheet ? 0.4 : state.kind == .fullScreen ? 0.85 : state.kind == .pod ? 0 : 0.15)
                .animation(spring, value: state.kind)
            VStack {
                Spacer()
                TabBarPreview(config: config, selectedTab: .constant(.dashboard), width: phone.width - 32, hidesPodContent: true)
                    .allowsHitTesting(false)
                    .padding(.bottom, 24)
                    .opacity(state.kind == .fullScreen ? 0 : 1)
                    .animation(spring, value: state.kind)
            }
            // The menu, out of the pod's slot. Drawn under the pod so its
            // own disc sits behind the glass.
            if spec.tap == .menu {
                LabGooeyMenu(frame: frame.applying(spec.action, config: config),
                             center: podHome, open: step == .menu,
                             since: step == .menu ? sinceChange : (index > 1 && auto ? sinceChange + Double(index - 2) * hold : sinceChange),
                             icons: spec.items.map(\.symbol), drawsButton: false)
                    .opacity(state.kind == .pod ? 1 : 0)
                    .animation(spring, value: state.kind)
            }
            LabMorphPanel(state: state, frame: panelFrame, config: config,
                          sinceChange: state.kind == .pod ? .infinity : surfaceAge,
                          untilChange: untilClose,
                          caption: verb.caption)
                .position(home)
                .animation(spring, value: state.kind)
            if showChrome {
                VStack(spacing: 4) {
                    Text(Self.title(of: step))
                        .font(.system(size: 15, weight: .semibold))
                        .contentTransition(.numericText())
                        .animation(spring, value: step)
                    Text(steps.count > 1 ? "Tap to step · hold to talk" : "Hold to talk")
                        .font(.caption)
                        .opacity(0.6)
                    if spec.filled < spec.total {
                        Text("\(spec.total - spec.filled) empty slots play as defaults")
                            .font(.caption2)
                            .opacity(0.5)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(.black.opacity(0.35)))
                .padding(.top, 60)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(width: phone.width, height: phone.height)
        .clipShape(RoundedRectangle(cornerRadius: 50, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 50, style: .continuous).strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
    }
}

// MARK: - The stage: play beside the board

struct LabSystemStage: View {
    @ObservedObject var lab: LabState
    @ObservedObject var config: RingConfig
    let frame: LabFrame
    @StateObject private var specs = LabSpecStore()

    var body: some View {
        let scale = frame.diameter * 1.9 / LabMorphView.phone.height
        HStack(alignment: .top, spacing: 24) {
            LabPlayView(frame: frame, config: config)
                .scaleEffect(scale)
                .frame(width: LabMorphView.phone.width * scale, height: LabMorphView.phone.height * scale)
                .contentShape(Rectangle())
                .onTapGesture { lab.advance() }
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { _ in lab.beginHold() }
                    .onEnded { _ in lab.endHold() })
            ScrollView(.vertical) {
                LabSpecBoard(lab: lab, config: config, frame: frame, specs: specs)
                    .padding(.trailing, 16)
            }
            .frame(width: 440)
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - The board

/// Every slot the product has, with what is in it. Filling one is a
/// "Use as…" from the Lab; here you see the whole, clear a slot, or send
/// its look back to the bench.
public struct LabSpecBoard: View {
    @ObservedObject var lab: LabState
    @ObservedObject var config: RingConfig
    let frame: LabFrame
    @ObservedObject var specs: LabSpecStore
    @State private var pasteFailed = false

    public init(lab: LabState, config: RingConfig, frame: LabFrame, specs: LabSpecStore) {
        self.lab = lab
        self.config = config
        self.frame = frame
        self.specs = specs
    }

    private var spec: LabSpec { lab.spec }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            group("Pod", "What lives in the tab bar at rest.") {
                slot(title: "Pod", look: spec.pod, clear: { lab.spec.pod = nil })
            }
            group("Agent states", "One look per verb. Their orb wears its nearest verb; any orb can take any state.") {
                LabWrap(spacing: 10) {
                    ForEach(LabAgentVerb.allCases) { verb in
                        slot(title: verb.label, look: spec.look(for: verb), clear: { lab.spec.states[verb.rawValue] = nil })
                    }
                }
            }
            group("Actions", "The menu a tap reveals, and what is in it.") {
                HStack(alignment: .top, spacing: 14) {
                    slot(title: "Menu", look: spec.action, clear: { lab.spec.action = nil }, subtitle: spec.action.map { LabExperiment.gooey.parameters.first!.choices![Int($0.values["gooey.effect"] ?? 0)] })
                    VStack(alignment: .leading, spacing: 6) {
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
                        Text(spec.items.map(\.label).joined(separator: " · "))
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            group("Surfaces", "What each action opens. Assign from a Morph state's menu; unassigned ones open the default.") {
                LabWrap(spacing: 10) {
                    ForEach(spec.items) { item in
                        surfaceSlot(item)
                    }
                }
            }
            group("Gestures", "What the two touches on the pod do.") {
                Picker("Tap", selection: Binding(get: { lab.spec.tap }, set: { lab.spec.tap = $0 })) {
                    ForEach(LabGestureResult.allCases) { Text($0.label).tag($0) }
                }
                Picker("Long press", selection: Binding(get: { lab.spec.longPress }, set: { lab.spec.longPress = $0 })) {
                    ForEach(LabGestureResult.allCases) { Text($0.label).tag($0) }
                }
            }
        }
        .padding(.vertical, 8)
    }

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
            Text("Fill a slot with “Use as…” on any orb, Gooey or Morph state; right-click a filled slot to open it in the Lab or clear it. JSON travels to Nexus Lab on the phone through Paste.")
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

    private func group<Content: View>(_ title: String, _ caption: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(caption).font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            content()
        }
    }

    /// One orb slot: the look at pod size in the pod's glass, or a gap.
    private func slot(title: String, look: LabLook?, clear: @escaping () -> Void, subtitle: String? = nil) -> some View {
        VStack(spacing: 6) {
            ZStack {
                if let look, look.experimentCase == .gooey {
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
            .contextMenu {
                if let look {
                    Button("Open in Lab") { lab.open(look) }
                    Button("Clear", role: .destructive, action: clear)
                }
            }
            Text(title).font(.caption.weight(.semibold))
            Text(subtitle ?? look?.title ?? "Empty")
                .font(.caption2)
                .foregroundStyle(look == nil ? .tertiary : .secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 96)
        }
        .frame(width: 100)
    }

    /// One surface slot: the Morph panel the action opens, small.
    private func surfaceSlot(_ item: LabActionItem) -> some View {
        let assigned = spec.surface(for: item)
        let surface = spec.resolvedSurface(for: item)
        let real = LabMorphPanel.size(of: surface.kind)
        let box: CGFloat = 140
        let scale = min(box / real.width, box / real.height, 1)
        let look = spec.resolvedLook(for: .listening)
        return VStack(spacing: 6) {
            LabMorphPanel(state: surface.morphState, frame: frame.applying(look, config: config).applying(surface), config: config, caption: LabAgentVerb.listening.caption)
                .scaleEffect(scale)
                .frame(width: box, height: box)
                .opacity(assigned == nil ? 0.45 : 1)
                .contextMenu {
                    if assigned != nil {
                        Button("Open in Lab") { lab.open(surface) }
                        Button("Clear", role: .destructive) { lab.spec.surfaces[item.rawValue] = nil }
                    }
                }
            Label(item.label, systemImage: item.symbol).font(.caption.weight(.semibold))
            Text(assigned == nil ? "Default · \(surface.kind.label)" : surface.kind.label + (surface.adornments.isEmpty ? "" : " · " + surface.adornments.map(\.label).joined(separator: ", ")))
                .font(.caption2)
                .foregroundStyle(assigned == nil ? .tertiary : .secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: box)
        }
        .frame(width: box + 4)
    }
}

/// A 62pt pod in Liquid Glass — the tab bar's, for thumbnails.
struct LabPodGlass<Content: View>: View {
    @ObservedObject var config: RingConfig
    let dark: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        let inner = content()
            .frame(width: 62, height: 62)
            .clipShape(Circle())
        Group {
            if #available(iOS 26.0, macOS 26.0, *) {
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
