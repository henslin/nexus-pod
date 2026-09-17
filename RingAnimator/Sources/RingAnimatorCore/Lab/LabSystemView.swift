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
    static func steps(of spec: LabSpec, withError: Bool = false) -> [Step] {
        var steps: [Step] = [.idle]
        let item: LabActionItem? = spec.tap.item ?? (spec.tap == .menu ? (spec.items.contains(.talk) ? .talk : spec.items.first) : nil)
        if spec.tap == .menu { steps.append(.menu) }
        if let item {
            var verbs: [LabAgentVerb] = [.listening, .thinking, .searching, .speaking, .done]
            if withError { verbs.insert(.error, at: 3) }
            for verb in verbs { steps.append(.surface(item, verb)) }
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
        let steps = Self.steps(of: spec, withError: frame.p("error", .system) >= 0.5)
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
        // A hold that asks for the whole screen gets it, whatever Talk's
        // container is — same adornments, full-screen shape.
        let held = frame.holding > 0 || frame.sinceHold < talk
        let surface: LabSurfaceSpec = {
            guard let item else { return LabSurfaceSpec(kind: .pod) }
            var s = spec.resolvedSurface(for: item)
            if held, spec.longPress.isFullScreen { s.kind = .fullScreen }
            return s
        }()
        let state = surface.morphState
        let look = spec.resolvedLook(for: verb)
        let panelFrame = frame.applying(look, config: config).applying(surface)
        // The content's transition clock runs from when the surface
        // opened, not from each verb — the verbs change inside it.
        let firstSurface = steps.firstIndex { if case .surface = $0 { return true } else { return false } } ?? index
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
        let showChrome = frame.p("chrome", .system) >= 0.5

        return ZStack {
            LabPhoneBackdrop(frame: frame, tab: onAnotherScreen ? .devices : .dashboard, size: phone)
                .animation(.easeInOut(duration: 0.25), value: onAnotherScreen)
            Color.black.opacity(state.kind == .sheet ? 0.4 : state.kind == .fullScreen ? state.dim : state.kind == .pod ? 0 : 0.15)
                .animation(spring, value: state.kind)
            VStack {
                Spacer()
                TabBarPreview(config: config, selectedTab: .constant(onAnotherScreen ? .devices : .dashboard), width: phone.width - LabPhone.inset * 2, hidesPodContent: true)
                    .allowsHitTesting(false)
                    .padding(.bottom, LabPhone.bottom)
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
            // A typed ask in a container that floats — the pill, the
            // card — brings the keyboard up from the bottom of the phone
            // and lifts the container above it. The sheet and the full
            // screen hold their own.
            let keyboardUp = conversation?.typing != nil && (state.kind == .pill || state.kind == .card) && !onAnotherScreen
            let lift: CGFloat = keyboardUp ? LabKeyboardView.height - 62 - LabPhone.bottom : 0
            ZStack(alignment: .bottom) {
                Color.clear
                if let t = conversation?.typing, keyboardUp {
                    LabKeyboardView(text: script.ask, typed: t.typed, phase: t.phase, width: phone.width)
                        .transition(.move(edge: .bottom))
                }
            }
            .animation(spring, value: keyboardUp)
            LabMorphPanel(state: state, frame: panelFrame, config: config,
                          sinceChange: state.kind == .pod ? .infinity : surfaceAge,
                          untilChange: untilClose,
                          caption: verb.caption,
                          conversation: conversation)
                .position(onAnotherScreen ? podHome : home)
                .offset(y: -lift)
                .animation(spring, value: state.kind)
                .animation(spring, value: keyboardUp)
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
        .clipShape(RoundedRectangle(cornerRadius: AnimationExporter.phoneScreenCornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AnimationExporter.phoneScreenCornerRadius, style: .continuous).strokeBorder(Color.white.opacity(frame.screen == nil ? 0.15 : 0), lineWidth: 1))
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
        let steps = LabPlayView.steps(of: frame.spec, withError: frame.p("error", .system) >= 0.5)
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
    }
}

// MARK: - The board

/// Every slot the product has, with what is in it — Q Branch's rail,
/// read down like an inspector: rows in tables, a menu per slot to fill
/// it (from the bench as it stands, a saved preset, or the Lab — the
/// rail there shows the errand and a Use button), containers edited in
/// place, sections that fold and still say what they hold.
public struct LabSpecBoard: View {
    @ObservedObject var lab: LabState
    @ObservedObject var config: RingConfig
    let frame: LabFrame
    @ObservedObject var specs: LabSpecStore
    /// A live frame for the thumbnails and the popovers.
    let frameAt: (Date) -> LabFrame
    @StateObject private var presets = LabPresetStore()
    @State private var pasteFailed = false

    public init(lab: LabState, config: RingConfig, frame: LabFrame, specs: LabSpecStore, frameAt: ((Date) -> LabFrame)? = nil) {
        self.lab = lab
        self.config = config
        self.frame = frame
        self.specs = specs
        self.frameAt = frameAt ?? { _ in frame }
    }

    private var spec: LabSpec { lab.spec }
    private static let thumb: CGFloat = 36
    #if os(macOS)
    @Environment(\.controlActiveState) private var activeState
    #endif

    /// One clock for every thumbnail on the board, at 30 fps — and none
    /// while the window isn't key. Only the thumbnails observe it; the
    /// pickers and fields don't rebuild on its tick. Nobody judges an
    /// orb's motion at 36 pt; they judge it on the phone.
    @StateObject private var clock = LabThumbClock()

    public var body: some View {
        #if os(macOS)
        let live = activeState != .inactive
        #else
        let live = true
        #endif
        board(frame)
            .onAppear { clock.frameAt = frameAt; clock.run(live) }
            .onChange(of: live) { _, l in clock.run(l) }
            .onDisappear { clock.run(false) }
    }

    private func board(_ frame: LabFrame) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            LabRailSection("q.pod", "Pod", summary: spec.pod?.title ?? "Empty") {
                slotRow(frame, title: "At rest", look: spec.pod, target: .pod, set: { lab.spec.pod = $0 })
            }
            LabRailSection("q.states", "Agent States", summary: "\(spec.states.count) of \(LabAgentVerb.allCases.count)") {
                ForEach(LabAgentVerb.allCases) { verb in
                    slotRow(frame, title: verb.label, symbol: verb.symbol, look: spec.look(for: verb), target: .state(verb), set: { lab.spec.states[verb.rawValue] = $0 })
                }
            } trailing: {
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
            }
            LabRailSection("q.ask", "Ask", summary: "\((spec.askStyle ?? .goo).label) · \((spec.askPlacement ?? .floating).label) · \(spec.items.count) items") {
                slotRow(frame, title: "Button", symbol: "sparkles", look: spec.ask, target: .ask, set: { lab.spec.ask = $0 }, menu: true)
                slotRow(frame, title: "Menu", symbol: "plus.circle", look: spec.action, target: .action, set: { lab.spec.action = $0 }, menu: true)
                labelled("Placement") {
                    Picker("", selection: Binding(get: { lab.spec.askPlacement ?? .floating }, set: { lab.spec.askPlacement = $0 })) {
                        ForEach(LabAskPlacement.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.menu).controlSize(.small)
                }
                .help("Where the Ask button sits on screens that aren't the Nexus tab.")
                VStack(alignment: .leading, spacing: 4) {
                    Text("Style").font(.callout).foregroundStyle(.secondary)
                    Picker("", selection: Binding(get: { lab.spec.askStyle ?? .goo }, set: { lab.spec.askStyle = $0 })) {
                        ForEach(LabAskStyle.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.segmented).controlSize(.small)
                }
                .help("What the Ask button is. In the pod, the pod is the button.")
                // The menu's items: checked is in, in this order.
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Menu items").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(spec.items.count) in the menu").font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.top, 4)
                    ForEach(LabActionItem.allCases) { item in
                        let on = spec.items.contains(item)
                        HStack(spacing: 8) {
                            Toggle("", isOn: Binding(get: { on }, set: { _ in lab.toggleItem(item) }))
                                .labelsHidden()
                            Image(systemName: item.symbol)
                                .font(.callout)
                                .frame(width: 20)
                                .foregroundStyle(on ? .primary : .tertiary)
                            Text(item.label)
                                .font(.callout)
                                .foregroundStyle(on ? .primary : .secondary)
                            Spacer(minLength: 0)
                            if on, let i = spec.items.firstIndex(of: item) {
                                Text("\(i + 1)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                            }
                        }
                        .help(on ? "In the menu, position \((spec.items.firstIndex(of: item) ?? 0) + 1). Uncheck to leave it out." : "Not in the menu. Check to add it at the end.")
                    }
                }
            }
            LabRailSection("q.containers", "Containers", summary: spec.items.map { "\($0.label) · \(spec.resolvedSurface(for: $0).kind.label)" }.joined(separator: ", ")) {
                containerTable
            }
            LabRailSection("q.quidgets", "Quidgets", summary: "\(spec.quidgetKinds.map(\.label).joined(separator: ", ")) · \(spec.quidgetInlineSize.label)") {
                Text("Quick widgets a reply can carry — the thing you asked about, as a control. Play a conversation that has one: Dim the patio light, Arm the house, Packages today.")
                    .font(.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(QuidgetKind.allCases) { kind in
                    HStack(spacing: 8) {
                        Toggle("", isOn: Binding(get: { spec.quidgetKinds.contains(kind) }, set: { on in
                            var kinds = spec.quidgetKinds
                            if on { if !kinds.contains(kind) { kinds.append(kind) } } else { kinds.removeAll { $0 == kind } }
                            lab.spec.quidgets = kinds
                        }))
                        .labelsHidden()
                        Image(systemName: kind.symbol)
                            .font(.callout).frame(width: 20).foregroundStyle(.secondary)
                        Text(kind.label).font(.callout)
                        Spacer(minLength: 0)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("In the reply").font(.callout).foregroundStyle(.secondary)
                    Picker("", selection: Binding(get: { spec.quidgetInlineSize }, set: { lab.spec.quidgetSize = $0.rawValue })) {
                        Text("Small").tag(QuidgetSize.small)
                        Text("Medium").tag(QuidgetSize.medium)
                    }
                    .labelsHidden().pickerStyle(.segmented).controlSize(.small)
                }
                .help("How a quidget sits in the reply. Clips are always medium. Tap one to expand it.")
                Button("Open the Quidgets Lab") { lab.experiment = .quidgets }
                    .controlSize(.small)
            }
            LabRailSection("q.gestures", "Gestures", summary: "Tap · \(spec.tap.label) · Hold · \(spec.longPress.label)") {
                labelled("Tap") {
                    Picker("", selection: Binding(get: { lab.spec.tap }, set: { lab.spec.tap = $0 })) {
                        ForEach(LabGestureResult.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.menu).controlSize(.small)
                }
                labelled("Long press") {
                    Picker("", selection: Binding(get: { lab.spec.longPress }, set: { lab.spec.longPress = $0 })) {
                        ForEach(LabGestureResult.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.menu).controlSize(.small)
                }
            }
            LabRailSection("q.play", "Play", defaultOpen: false) {
                LabKnobList(lab: lab, experiment: .system)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Spec name", text: Binding(get: { lab.spec.name }, set: { lab.spec.name = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .font(.headline)
                specsMenu
            }
            HStack(spacing: 10) {
                Text("\(spec.filled) of \(spec.total) slots")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Copy JSON") { LabSpecStore.copy(spec) }
                    .help("The spec as JSON, for Nexus Lab's Paste Spec on the phone.")
                Button("Paste") {
                    if let s = LabSpecStore.paste() { lab.spec = s; pasteFailed = false } else { pasteFailed = true }
                }
                .help("A spec from the pasteboard.")
            }
            .font(.caption)
            .buttonStyle(.borderless)
            if pasteFailed {
                Text("The pasteboard doesn't hold a spec.").font(.caption).foregroundStyle(.red)
            }
        }
        .padding(14)
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
            Image(systemName: "square.stack")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Saved specs and starters")
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

    // MARK: Slots

    /// One slot as a row — see `LabSlotRow`.
    private func slotRow(_ frame: LabFrame, title: String, symbol: String? = nil, look: LabLook?, target: LabSlotTarget, set: @escaping (LabLook?) -> Void, menu: Bool = false) -> some View {
        LabSlotRow(lab: lab, config: config, clock: clock, frameAt: frameAt, title: title, symbol: symbol, look: look, target: target, set: set, isMenu: menu, presets: presets)
    }

    // MARK: Containers

    /// One table: item · kind · carries · in · out, a row per item in
    /// the menu. Edited in place.
    private var containerTable: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Item").frame(width: 66, alignment: .leading)
                Text("Kind").frame(width: 88, alignment: .leading)
                Text("Carries").frame(minWidth: 96, maxWidth: .infinity, alignment: .leading)
                Text("In").frame(width: 58, alignment: .leading)
                Text("Out").frame(width: 58, alignment: .leading)
                Spacer().frame(width: 20)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            Divider()
            ForEach(spec.items) { item in
                containerRow(item)
            }
        }
    }

    private func containerRow(_ item: LabActionItem) -> some View {
        LabContainerRow(lab: lab, config: config, frameAt: frameAt, item: item)
    }
}

/// One row of the containers table: item · kind · carries · in · out ·
/// sliders. The sliders open the container's editor — backdrop, hero
/// size, dim, the morph's knobs.
struct LabContainerRow: View {
    @ObservedObject var lab: LabState
    @ObservedObject var config: RingConfig
    let frameAt: (Date) -> LabFrame
    let item: LabActionItem
    @State private var editing = false

    private var assigned: LabSurfaceSpec? { lab.spec.surface(for: item) }
    private var surface: LabSurfaceSpec { lab.spec.resolvedSurface(for: item) }
    private var binding: Binding<LabSurfaceSpec> {
        Binding(get: { lab.spec.resolvedSurface(for: item) }, set: { lab.spec.surfaces[item.rawValue] = $0 })
    }

    var body: some View {
        let surface = surface
        HStack(spacing: 8) {
            Label(item.label, systemImage: item.symbol)
                .font(.callout)
                .lineLimit(1)
                .frame(width: 66, alignment: .leading)
                .foregroundStyle(assigned == nil ? .secondary : .primary)
            Picker("", selection: Binding(get: { surface.kind }, set: { v in binding.wrappedValue.kind = v })) {
                ForEach(LabMorphKind.offered) { Text($0.label).tag($0) }
            }
            .labelsHidden().pickerStyle(.menu).controlSize(.small)
            .frame(width: 88, alignment: .leading)
            Menu {
                ForEach(LabMorphAdornment.allCases) { a in
                    let on = surface.adornments.contains(a)
                    Button {
                        var s = surface
                        if on { s.adornments.removeAll { $0 == a } } else { s.adornments.append(a) }
                        lab.spec.surfaces[item.rawValue] = s
                    } label: {
                        Label(a.label, systemImage: on ? "checkmark" : a.symbol)
                    }
                }
                if assigned != nil {
                    Divider()
                    Button("Open in Morph") { lab.open(surface) }
                    Button("Reset to Default", role: .destructive) { lab.spec.surfaces[item.rawValue] = nil }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(surface.adornments.isEmpty ? "None" : surface.adornments.map(\.label).joined(separator: ", "))
                        .font(.callout)
                        .foregroundStyle(surface.adornments.isEmpty ? .tertiary : .primary)
                        .lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(minWidth: 96, maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
            .controlSize(.small)
            .frame(minWidth: 96, maxWidth: .infinity, alignment: .leading)
            Picker("", selection: Binding(get: { surface.enter }, set: { v in binding.wrappedValue.enter = v })) {
                ForEach(LabMorphTransition.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden().pickerStyle(.menu).controlSize(.small)
            .frame(width: 58, alignment: .leading)
            Picker("", selection: Binding(get: { surface.exit }, set: { v in binding.wrappedValue.exit = v })) {
                ForEach(LabMorphTransition.allCases.filter { $0 != .flare }) { Text($0.label).tag($0) }
            }
            .labelsHidden().pickerStyle(.menu).controlSize(.small)
            .frame(width: 58, alignment: .leading)
            Button { editing = true } label: { Image(systemName: "slider.horizontal.3") }
                .buttonStyle(.borderless)
                .font(.caption)
                .help("Backdrop, hero size, dim, the morph's knobs")
                .popover(isPresented: $editing, arrowEdge: .leading) {
                    LabContainerEditor(item: item, surface: binding, frameAt: frameAt, config: config)
                }
        }
        .help(assigned == nil ? "The default for \(item.label). Change anything to make it this spec's own." : "\(item.label) opens a \(surface.kind.label).")
    }
}

/// One slot: thumbnail · name · what's in it · sliders · ⋯. Click the
/// thumbnail or name to choose from the gallery (orbs) or open the
/// editor (the goo); the sliders glyph tunes the look in place; ⋯ keeps
/// the bench, presets and clear.
struct LabSlotRow: View {
    @ObservedObject var lab: LabState
    @ObservedObject var config: RingConfig
    /// The board's shared clock; only the thumbnail listens.
    let clock: LabThumbClock
    let frameAt: (Date) -> LabFrame
    let title: String
    var symbol: String? = nil
    let look: LabLook?
    let target: LabSlotTarget
    let set: (LabLook?) -> Void
    var isMenu = false
    @ObservedObject var presets: LabPresetStore
    @State private var choosing = false
    @State private var editing = false

    private static let thumb: CGFloat = 36

    /// The look, bound into the spec for the editor.
    private var lookBinding: Binding<LabLook> {
        Binding(get: { look ?? LabLook(experiment: isMenu ? LabExperiment.gooey.id : LabExperiment.aurora.id) }, set: { set($0) })
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                if isMenu { editing = true } else { choosing = true }
            } label: {
                HStack(spacing: 10) {
                    thumbnail
                        .frame(width: Self.thumb, height: Self.thumb)
                    if let symbol {
                        Image(systemName: symbol).font(.caption).foregroundStyle(.secondary).frame(width: 14)
                    }
                    Text(title).font(.callout)
                        .frame(width: symbol == nil ? LabRailMetrics.labelWidth : LabRailMetrics.labelWidth - 24, alignment: .leading)
                    Text(look.map { $0.experimentCase == .gooey ? gooeyEffectName($0) : $0.title } ?? "Empty — click to choose")
                        .font(.callout)
                        .foregroundStyle(look == nil ? .tertiary : .secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isMenu ? "Tune the goo" : "Choose an orb for this slot")
            .popover(isPresented: $choosing, arrowEdge: .leading) {
                LabOrbGallery(frameAt: frameAt, config: config, current: look) { set($0) }
            }
            if look != nil || isMenu {
                Button { editing = true } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .help("Tune this look in place")
                    .popover(isPresented: $editing, arrowEdge: .leading) {
                        LabLookEditor(look: lookBinding, frameAt: frameAt, config: config) { lab.edit(lookBinding.wrappedValue, for: target) }
                    }
            }
            Menu {
                actions
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .font(.caption)
        }
        .contextMenu { actions }
    }

    @ViewBuilder
    private var actions: some View {
        if !isMenu {
            Button { choosing = true } label: { Label("Choose from the Gallery…", systemImage: "square.grid.2x2") }
        }
        if look != nil || isMenu {
            Button { editing = true } label: { Label("Tune in Place…", systemImage: "slider.horizontal.3") }
        }
        Button {
            lab.edit(look, for: target)
        } label: { Label("Full Rail on the Bench…", systemImage: "flask") }
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
        if look != nil {
            Divider()
            Button("Clear", role: .destructive) { set(nil) }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let look, isMenu {
            let fillChoice = Int(look.values["gooey.fill"] ?? 1)
            let f = frameAt(Date())
            let fill: Color = [Color(white: 0.13), Color(white: 0.92), Color(hex: "#5AC8FA"), Color(hex: "#FFCF9E"), f.colors.first ?? .white][min(max(fillChoice, 0), 4)]
            ZStack {
                Circle().fill(fill)
                Image(systemName: "plus").font(.system(size: 14, weight: .semibold)).foregroundStyle(fillChoice == 0 ? .white : Color(white: 0.1))
            }
        } else if let look {
            LabLiveThumb(clock: clock, look: look, config: config, size: Self.thumb)
        } else {
            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(.tertiary)
        }
    }

    private func gooeyEffectName(_ look: LabLook) -> String {
        let choices = LabExperiment.gooey.parameters.first { $0.id == "effect" }?.choices ?? []
        let i = Int(look.values["gooey.effect"] ?? 0)
        return choices.indices.contains(i) ? "Gooey · \(choices[i])" : "Gooey"
    }
}

/// The board's thumbnail clock: one frame, 30 times a second, while it
/// runs. Thumbnails observe it; nothing else does.
@MainActor
final class LabThumbClock: ObservableObject {
    @Published private(set) var frame: LabFrame?
    var frameAt: ((Date) -> LabFrame)?
    var fps: Double = 30
    private var timer: Timer?

    func run(_ on: Bool) {
        timer?.invalidate()
        timer = nil
        guard on else { return }
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 1 / fps, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }
    private func tick() { frame = frameAt?(Date()) }
}

/// A look as a flat pod on the board's clock.
struct LabLiveThumb: View {
    @ObservedObject var clock: LabThumbClock
    let look: LabLook
    @ObservedObject var config: RingConfig
    let size: CGFloat

    var body: some View {
        if let f = clock.frame {
            LabPodGlass(config: config, dark: f.darkStage, flat: true) {
                LabHeroView(frame: f.applying(look, config: config), config: config, diameter: 62)
            }
            .scaleEffect(size / 62)
        } else {
            Circle().fill(.quaternary)
        }
    }
}

/// A 62pt pod in Liquid Glass — the tab bar's, for thumbnails.
struct LabPodGlass<Content: View>: View {
    @ObservedObject var config: RingConfig
    let dark: Bool
    /// A tinted circle with a highlight instead of Liquid Glass — for
    /// thumbnails, where a live glass pass per row is the expensive part
    /// and nobody can tell at 36 pt.
    var flat = false
    @ViewBuilder let content: () -> Content
    @Environment(\.labNoGlass) private var noGlass

    var body: some View {
        let inner = content()
            .frame(width: 62, height: 62)
            .clipShape(Circle())
        Group {
            if noGlass || flat {
                inner
                    .background(Circle().fill(dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)))
                    .overlay(Circle().strokeBorder(dark ? Color.white.opacity(0.18) : Color.black.opacity(0.12), lineWidth: 1))
                    .overlay(alignment: .top) {
                        // The glass's rim light, painted.
                        Ellipse().fill(Color.white.opacity(dark ? 0.12 : 0.35)).frame(width: 34, height: 10).blur(radius: 3).offset(y: 3)
                    }
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
            Label("Use in Q Branch…", systemImage: "wrench.and.screwdriver")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
