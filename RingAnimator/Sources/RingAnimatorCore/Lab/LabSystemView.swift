import SwiftUI

// Q Branch: the spec on a phone — autoplayed, or in your hand — and the
// board of slots beside it. See `LabSpec.swift` for the model and the
// why.

// MARK: - The room

/// Q Branch's stage: one switch. Autoplay is `LabPlayView`, the spec on
/// the clock; Interact is `LabAppView`, the same spec live, driven by
/// you. The mode is the room's first knob, so it rides with the frame
/// and reaches the phone with the rest.
public struct LabQBranchView: View {
    let frame: LabFrame
    @ObservedObject var config: RingConfig

    public init(frame: LabFrame, config: RingConfig) {
        self.frame = frame
        self.config = config
    }

    public var body: some View {
        let interact = frame.p("mode", .system) >= 0.5
        let _ = Self.trace(interact: interact, frame: frame)
        if interact {
            LabAppView(frame: frame, config: config)
        } else {
            LabPlayView(frame: frame, config: config)
        }
    }
    nonisolated(unsafe) private static var last = ""
    private static func trace(interact: Bool, frame: LabFrame) {
        guard LabTrace.on else { return }
        let auto = frame.p("auto", .system) >= 0.5
        let pos = LabPlayView.position(in: frame.flow, frame: frame, auto: auto)
        let line = "stage interact=\(interact) auto=\(auto) taps=\(frame.taps) index=\(pos.index) holding=\(frame.holding > 0) sinceHold<3=\(frame.sinceHold < 3)"
        if line != last { last = line; LabTrace.log(line) }
    }
}

/// Under the phone on the Mac: the transport in Autoplay; in Interact
/// the same transport, since the flow is also the checklist you're
/// driving through.
struct LabQBranchStrip: View {
    @ObservedObject var lab: LabState
    let frame: LabFrame

    var body: some View {
        LabTransport(lab: lab, frame: frame)
    }
}

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

    /// What a frame of the play shows — the flow's step, resolved.
    enum Step: Equatable {
        case idle, menu
        case surface(LabActionItem, LabAgentVerb)
        /// The Ask button on a screen that isn't the Nexus tab.
        case askAnywhere
        case askMenu

        init(_ step: LabStep) {
            switch step.phase {
            case .rest: self = .idle
            case .menu: self = .menu
            case .surface: self = .surface(step.item ?? .talk, step.verb == .idle ? .listening : step.verb)
            case .field: self = .surface(.ask, .listening)
            case .ask: self = .askAnywhere
            case .askMenu: self = .askMenu
            }
        }
    }

    /// For harnesses: how many steps a flow plays.
    public static func stepCount(of flow: LabFlow) -> Int { flow.steps.count }

    /// The keyboard is the screen's, full width at the bottom. A floating
    /// container lifts above it; the sheet shortens so it still floats,
    /// with its margin, above the keyboard.
    static func keyboardFit(kind: LabMorphKind, up: Bool, phone: CGSize) -> (lift: CGFloat, sheetHeight: CGFloat?) {
        guard up else { return (0, nil) }
        switch kind {
        case .pill, .card: return (LabKeyboardView.height - 62 - LabPhone.bottom, nil)
        case .sheet:
            let full = LabMorphPanel.size(of: .sheet).height
            let room = phone.height - LabKeyboardView.height - LabMorphPanel.sheetInset - 60
            let h = min(full, room)
            // Its home is set for the full height, so lifting by the
            // keyboard puts its bottom a margin above the keys; a
            // shorter sheet is centred, so its centre comes down by half
            // the difference to keep that bottom where it is.
            return (LabKeyboardView.height - (full - h) / 2, h)
        default: return (0, nil)
        }
    }

    /// Where the play is: the step, how long it has been there, and how
    /// long until it moves on. On the clock, each step holds for its own
    /// seconds; a tap moves on from wherever the clock has it. A hold
    /// overrides the sequence — the long-press action, listening while
    /// held, speaking for `talk` seconds after.
    static func position(in flow: LabFlow, frame: LabFrame, auto: Bool) -> (index: Int, since: Double, until: Double) {
        let n = max(flow.steps.count, 1)
        if auto {
            let (i, since) = flow.position(at: frame.time)
            let index = ((i + frame.taps) % n + n) % n
            let step = flow.steps.indices.contains(index) ? flow.steps[index] : LabStep()
            let s = min(since, frame.sinceTap)
            return (index, s, flow.duration(of: step) - s)
        }
        let index = ((frame.taps % n) + n) % n
        return (index, frame.sinceTap, .infinity)
    }

    public var body: some View {
        let flow = frame.flow
        let spec = flow.kit
        let steps = flow.steps.isEmpty ? [LabStep(.rest)] : flow.steps
        let auto = frame.p("auto", .system) >= 0.5
        let talk = frame.p("talk", .system)
        let script = flow.script
        let spring = Animation.spring(response: frame.p("spring", .system), dampingFraction: 1 - frame.p("bounce", .system) * 0.45)
        var (index, sinceChange, untilChange) = Self.position(in: flow, frame: frame, auto: auto)
        index = min(index, steps.count - 1)
        let current = steps[index]
        var step = Step(current)
        var held = false
        if let heldItem = spec.longPress.item ?? (spec.longPress == .menu ? .talk : nil) {
            if frame.holding > 0 {
                step = .surface(heldItem, .listening); sinceChange = frame.holding; untilChange = .infinity; held = true
            } else if frame.sinceHold < talk {
                step = .surface(heldItem, .speaking); sinceChange = frame.sinceHold; untilChange = talk - frame.sinceHold; held = true
            }
        }
        // What the panel is: the pod, or the action's surface.
        let item: LabActionItem? = { if case .surface(let i, _) = step { return i } else { return nil } }()
        let verb: LabAgentVerb = { if case .surface(_, let v) = step { return v } else { return .idle } }()
        // The kit's container for the action — or the one this step
        // insists on. A hold that asks for the whole screen gets it.
        let surface: LabSurfaceSpec = {
            guard let item else { return LabSurfaceSpec(kind: .pod) }
            var s = held ? spec.resolvedSurface(for: item) : (current.surface ?? spec.resolvedSurface(for: item))
            if held, spec.longPress.isFullScreen { s.kind = .fullScreen }
            // The ask field is a pill with the input in it.
            if !held, current.phase == .field { s.kind = .pill }
            return s
        }()
        let isField = !held && current.phase == .field
        let state = surface.morphState
        let look = held ? spec.resolvedLook(for: verb) : (current.look ?? spec.resolvedLook(for: verb))
        let panelFrame = frame.applying(look, config: config).applying(surface)
        // The content's transition clock runs from when the surface
        // opened, not from each verb — the verbs change inside it.
        let starts = flow.starts
        let surfaceRange = flow.surfaceRange
        let surfaceAge: Double = {
            if held { return sinceChange }
            guard auto, let r = surfaceRange, r.contains(index), starts.indices.contains(index), starts.indices.contains(r.lowerBound) else { return sinceChange }
            return sinceChange + (starts[index] - starts[r.lowerBound])
        }()
        let untilClose = (auto && index == surfaceRange?.upperBound) || frame.sinceHold < talk ? untilChange : .infinity
        let conversation: LabConversation? = item.map {
            var c = LabConversation(script: script, mode: $0 == .talk ? .voice : .text, verb: verb, since: sinceChange, age: surfaceAge)
            c.field = isField
            return c
        }
        let onAnotherScreen = step == .askAnywhere || step == .askMenu
        let tab: NexusTab = held ? .dashboard : current.tabCase
        let phone = LabMorphView.phone
        let home = LabMorphView.home(of: state.kind)
        let podHome = LabMorphView.home(of: .pod)
        let placement = spec.askPlacement ?? .floating
        let showChrome = frame.p("chrome", .system) >= 0.5
        // The menu's own clock: open on its step, closing from when the
        // step after it began.
        let menuIndex = steps.firstIndex { $0.phase == .menu }
        let menuSince: Double = {
            guard step != .menu, auto, let m = menuIndex, index > m, starts.indices.contains(index), starts.indices.contains(m + 1) else { return sinceChange }
            return sinceChange + (starts[index] - starts[m + 1])
        }()

        return ZStack {
            LabPhoneBackdrop(frame: frame, tab: tab.demoTab, size: phone)
                .animation(.easeInOut(duration: 0.25), value: tab)
            Color.black.opacity(state.kind == .sheet ? 0.4 : state.kind == .fullScreen ? state.dim : state.kind == .pod ? 0 : 0.15)
                .animation(spring, value: state.kind)
            VStack {
                Spacer()
                TabBarPreview(config: config, selectedTab: .constant(tab.demoTab), width: phone.width - LabPhone.inset * 2, hidesPodContent: true)
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
                             since: menuSince,
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
                             suggestions: (spec.askOffers ?? .actions) == .suggestions ? LabAskContext.devices : [])
            }
            // A typed ask in a container that floats — the pill, the
            // card — brings the keyboard up from the bottom of the phone
            // and lifts the container above it. The sheet and the full
            // screen hold their own.
            // The field arrives alone for a beat; the keyboard comes up
            // as the typing starts — the tap on the field, in effect.
            let keyboardUp = conversation?.typing != nil && (state.kind == .pill || state.kind == .card || state.kind == .sheet) && !onAnotherScreen && !(isField && sinceChange < 0.7)
            let (lift, sheetHeight) = Self.keyboardFit(kind: state.kind, up: keyboardUp, phone: phone)
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
                          conversation: conversation,
                          height: sheetHeight)
                .position(onAnotherScreen ? podHome : home)
                .offset(y: -lift)
                .animation(spring, value: state.kind)
                .animation(spring, value: keyboardUp)
            if showChrome {
                VStack(spacing: 3) {
                    Text(held ? (frame.holding > 0 ? "Listening" : "Speaking") : current.title)
                        .font(.system(size: 13, weight: .semibold))
                        .contentTransition(.numericText())
                        .animation(spring, value: step)
                    Text("\(index + 1) of \(steps.count) · \(flow.name)")
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

// MARK: - The transport

/// Under the phone: the transport. Previous, next, restart, the step
/// you're on and how many there are, the Auto switch — and nothing to
/// edit, because the steps live in the navigator now (Chris,
/// 2026-09-18). Slim enough to keep during a demo with the sidebar
/// folded away.
struct LabTransport: View {
    @ObservedObject var lab: LabState
    let frame: LabFrame

    var body: some View {
        let flow = frame.flow
        let auto = frame.p("auto", .system) >= 0.5
        let n = max(flow.steps.count, 1)
        let index = min(LabPlayView.position(in: flow, frame: frame, auto: auto).index, n - 1)
        let current = flow.steps.indices.contains(index) ? flow.steps[index] : nil
        HStack(spacing: 14) {
            HStack(spacing: 2) {
                Button { go(index - 1) } label: { Image(systemName: "backward.end.fill") }
                    .help("Previous step")
                Button { lab.taps = 0; lab.lastTap = Date() } label: { Image(systemName: "arrow.counterclockwise") }
                    .help("Restart")
                Button { go(index + 1) } label: { Image(systemName: "forward.end.fill") }
                    .help("Next step")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 13, weight: .semibold))
            HStack(spacing: 6) {
                if let current {
                    Image(systemName: current.symbol).font(.caption).foregroundStyle(.secondary).frame(width: 16)
                    Text(current.title).font(.callout.weight(.semibold)).lineLimit(1)
                }
                Text("\(index + 1) of \(n)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .frame(minWidth: 180, alignment: .leading)
            .contentTransition(.numericText())
            .animation(.default, value: index)
            Toggle("Auto", isOn: Binding(get: { auto }, set: { lab.values["system.auto"] = $0 ? 1 : 0; lab.taps = 0; lab.lastTap = Date() }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Steps on the clock — each step for its own seconds. Off, only the arrows, a tap on the phone, or the navigator move it.")
            Text(lab.qInteract ? "Tap the pod · type or hold to talk" : "Tap the phone to step · hold it to talk")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    /// Stop the clock at a step, and select it in the navigator.
    private func go(_ i: Int) {
        let n = max(lab.flow.steps.count, 1)
        let j = ((i % n) + n) % n
        guard lab.flow.steps.indices.contains(j) else { return }
        lab.go(to: lab.flow.steps[j])
    }
}

// MARK: - The board

/// Every slot the product has, with what is in it — Q Branch's rail,
/// read down like an inspector: rows in tables, a menu per slot to fill
/// it (from the bench as it stands, a saved preset, or the Lab — the
/// rail there shows the errand and a Use button), containers edited in
/// place, sections that fold and still say what they hold.
public struct LabSpecBoard: View {
    /// Which half of the board: the flow's own settings (the document),
    /// or the kit (the parts). The navigator picks.
    public enum Mode { case flow, kit }

    @ObservedObject var lab: LabState
    @ObservedObject var config: RingConfig
    let frame: LabFrame
    @ObservedObject var flows: LabFlowStore
    let mode: Mode
    /// A live frame for the thumbnails and the popovers.
    let frameAt: (Date) -> LabFrame
    @StateObject private var presets = LabPresetStore()
    @State private var pasteFailed = false

    public init(lab: LabState, config: RingConfig, frame: LabFrame, flows: LabFlowStore, mode: Mode = .flow, frameAt: ((Date) -> LabFrame)? = nil) {
        self.lab = lab
        self.config = config
        self.frame = frame
        self.flows = flows
        self.mode = mode
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

    @ViewBuilder
    private func board(_ frame: LabFrame) -> some View {
        switch mode {
        case .flow: flowBoard
        case .kit: kitBoard(frame)
        }
    }

    /// The document: its name, the flows menu, how it moves through
    /// the app, what replies may carry, and the play's own knobs. The
    /// steps themselves are in the navigator.
    private var flowBoard: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            LabRailSection("q.quidgets", "Quidgets", summary: "\(spec.quidgetKinds.map(\.label).joined(separator: ", ")) · \(spec.quidgetInlineSize.label)") {
                quidgetsSection
            }
            LabRailSection("q.gestures", "Gestures", summary: "Tap · \(spec.tap.label) · Hold · \(spec.longPress.label)") {
                gesturesSection
            }
            LabRailSection("q.play", "Autoplay · Interact", defaultOpen: false) {
                LabKnobList(lab: lab, experiment: .system)
            }
        }
    }

    /// The parts: the pod, a look per agent state, the Ask button and
    /// its menu, a container per action.
    private func kitBoard(_ frame: LabFrame) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Kit").font(.headline)
                Text("\(spec.filled) of \(spec.total) slots · the parts every step draws on")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(14)
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
                } label: { Image(systemName: "ellipsis.circle").accessibilityLabel("More") }
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
                VStack(alignment: .leading, spacing: 4) {
                    Text("Offers").font(.callout).foregroundStyle(.secondary)
                    Picker("", selection: Binding(get: { lab.spec.askOffers ?? .actions }, set: { lab.spec.askOffers = $0 })) {
                        ForEach(LabAskOffers.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.segmented).controlSize(.small)
                }
                .help("What the menu holds: the actions below, or suggestions about the screen you’re on. One or the other, not both.")
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
        }
    }

    // MARK: Flow sections

    @ViewBuilder private var quidgetsSection: some View {
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
    @ViewBuilder private var gesturesSection: some View {
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

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Flow name", text: Binding(get: { lab.flow.name }, set: { lab.flow.name = $0; lab.flow.kit.name = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .font(.headline)
                flowsMenu
            }
            HStack(spacing: 10) {
                Text("\(lab.flow.steps.count) steps · \(spec.filled) of \(spec.total) slots")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Copy JSON") { LabFlowStore.copy(lab.flow) }
                    .help("The flow as JSON, for Nexus Lab's Paste on the phone.")
                Button("Paste") {
                    if let f = LabFlowStore.paste() { lab.flow = f; lab.qSelection = .flow; pasteFailed = false } else { pasteFailed = true }
                }
                .help("A flow — or an older spec — from the pasteboard.")
            }
            .font(.caption)
            .buttonStyle(.borderless)
            if pasteFailed {
                Text("The pasteboard doesn't hold a flow.").font(.caption).foregroundStyle(.red)
            }
        }
        .padding(14)
    }

    private var flowsMenu: some View {
        Menu {
            if flows.flows.isEmpty {
                Text("No saved flows")
            } else {
                Section("Load") {
                    ForEach(flows.flows) { f in Button(f.name) { lab.flow = f; lab.qSelection = .flow } }
                }
                Menu("Delete") {
                    ForEach(flows.flows) { f in Button(f.name, role: .destructive) { flows.delete(f) } }
                }
            }
            Section("Starters") {
                ForEach(LabFlow.starters) { f in Button(f.name) { lab.flow = f; lab.qSelection = .flow } }
            }
            Divider()
            Button("Save “\(lab.flow.name)”") { flows.save(lab.flow) }
            Button("Save a Copy") { var f = lab.flow; f.id = UUID(); f.name += " copy"; f.kit.name = f.name; flows.save(f); lab.flow = f }
            Button("New Flow with This Kit") { lab.flow = LabFlow(name: "Untitled", kit: spec, steps: [LabStep(.rest)]); lab.qSelection = .flow }
            Button("New Flow", role: .destructive) { lab.flow = LabFlow(name: "Untitled", kit: LabSpec(), steps: [LabStep(.rest)]); lab.qSelection = .flow }
        } label: {
            Image(systemName: "square.stack")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Saved flows and starters")
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
            Button { editing = true } label: { Image(systemName: "slider.horizontal.3").accessibilityLabel("Tune") }
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
                Button { editing = true } label: { Image(systemName: "slider.horizontal.3").accessibilityLabel("Tune") }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .help("Tune this look in place")
                    .popover(isPresented: $editing, arrowEdge: .leading) {
                        LabLookEditor(look: lookBinding, frameAt: frameAt, config: config) { lab.edit(lookBinding.wrappedValue, for: target) }
                    }
            }
            Menu {
                actions
            } label: { Image(systemName: "ellipsis.circle").accessibilityLabel("More") }
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
