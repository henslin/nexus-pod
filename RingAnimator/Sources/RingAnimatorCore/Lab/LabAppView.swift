import SwiftUI

// The App: Q Branch's second lane.
//
// Chris, 2026-09-17: "two lanes. One that's auto-play. And the other is
// fully interactive and self driven." The Agent is the film — the spec
// played through every state on the clock. The App is the phone in
// your hand: the real screens, the tab bar with the pod, the spec's
// menu and surfaces — and you drive it. Tap a tab. Tap the pod and pick
// Ask; type an ask (the on-screen keyboard follows your keys) or tap a
// suggestion, and the agent answers with the closest script, doing the
// thing to the house as it does. Hold the pod to talk. Tap off to
// close. Nothing steps on its own but the agent's own thinking.

/// Where the app is: which tab, what's open, what's been asked.
@MainActor
public final class LabAppSession: ObservableObject {
    public static let shared = LabAppSession()

    @Published public var tab: DemoTab = .dashboard
    @Published public var menuOpen = false
    @Published public var menuAt = Date.distantPast
    /// The open surface, and when it opened.
    @Published public var surface: LabActionItem? = nil
    @Published public var surfaceAt = Date.distantPast
    /// A surface opened by a hold takes the hold's shape (full screen,
    /// if the spec says so) — remembered past the release.
    @Published public var byHold = false
    /// Opened as the ask field: a pill with the input in it, until the
    /// ask is sent — then Ask's own container.
    @Published public var asField = false
    /// The field, switched to voice.
    @Published public var fieldVoice = false
    /// The ask being typed, and the last keystroke.
    @Published public var draft = ""
    @Published public var keyAt = Date.distantPast
    /// The ask, once sent: the script it matched and when.
    @Published public var script: LabScript? = nil
    @Published public var askedAt: Date? = nil
    @Published public var holding = false

    public init() {}

    /// The beats of an answer, in seconds after the ask.
    static let thinking = 1.1
    static let searching = 1.9

    /// What the agent's surface shows right now.
    func conversation(at date: Date, defaultScript: LabScript, transcript: String?) -> LabConversation? {
        guard let surface, surface == .ask || surface == .talk else { return nil }
        let mode: LabConversation.Mode = surface == .talk ? .voice : .text
        let age = date.timeIntervalSince(surfaceAt)
        guard let askedAt, let script else {
            var c = LabConversation(script: defaultScript, mode: showingField && fieldVoice ? .voice : mode, verb: .listening, since: age, age: age)
            if c.mode == .text {
                c.typedAsk = draft
                c.sinceKey = date.timeIntervalSince(keyAt)
            }
            c.field = showingField
            return c
        }
        let t = date.timeIntervalSince(askedAt)
        let words = Double(script.answer.split(separator: " ").count)
        let verb: LabAgentVerb
        let since: Double
        if t < Self.thinking { verb = .thinking; since = t }
        else if t < Self.thinking + Self.searching { verb = .searching; since = t - Self.thinking }
        else if t < Self.thinking + Self.searching + words / 9 + 0.4 { verb = .speaking; since = t - Self.thinking - Self.searching }
        else { verb = .done; since = t - Self.thinking - Self.searching - words / 9 - 0.4 }
        var c = LabConversation(script: script, mode: mode, verb: verb, since: since, age: age)
        if mode == .text { c.typedAsk = draft.isEmpty ? nil : draft }
        return c
    }

    // MARK: Driving it

    public func tapPod(spec: LabSpec) {
        if surface != nil { close(); return }
        switch spec.tap {
        case .menu: toggleMenu()
        case .nothing: break
        case .field: open(.ask, asField: true)
        default: open(spec.tap.item ?? .ask)
        }
    }

    public func toggleMenu() {
        menuOpen.toggle()
        menuAt = Date()
    }

    public func choose(_ item: LabActionItem) {
        menuOpen = false
        menuAt = Date()
        open(item)
    }

    public func open(_ item: LabActionItem, byHold: Bool = false, asField: Bool = false) {
        surface = item
        surfaceAt = Date()
        self.byHold = byHold
        self.asField = asField
        fieldVoice = false
        draft = ""
        script = nil
        askedAt = nil
    }
    /// The field's mic / keyboard glyph.
    public func toggleVoice() { fieldVoice.toggle() }
    /// Whether the field is what's showing: opened as one, and nothing
    /// sent yet.
    public var showingField: Bool { asField && askedAt == nil && surface == .ask }

    /// Hold the pod: the long-press action, listening while held.
    public func beginHold(spec: LabSpec) {
        guard surface == nil, !holding else { return }
        holding = true
        switch spec.longPress {
        case .nothing: holding = false
        case .menu: toggleMenu()
        case .fullScreen: open(.talk, byHold: true)
        default: open(spec.longPress.item ?? .talk, byHold: true)
        }
    }

    /// Let go: the ask is made (the transcript, or the script's ask).
    public func endHold(transcript: String?, defaultScript: LabScript) {
        guard holding else { return }
        holding = false
        if surface == .talk, askedAt == nil {
            // Too quick to be a hold: treat as a tap and go back.
            if Date().timeIntervalSince(surfaceAt) < 0.35 { close(); return }
            script = LabScript.matching(transcript ?? "") ?? defaultScript
            askedAt = Date()
        }
    }

    public func submit(_ text: String, defaultScript: LabScript) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        draft = trimmed
        script = LabScript.matching(trimmed) ?? defaultScript
        askedAt = Date()
    }

    public func typed(_ text: String) {
        draft = text
        keyAt = Date()
    }

    /// Put the live app into a step's state, to drive on from there:
    /// the tab, the menu open, the field up, the container at that
    /// state with the flow's own words. Selecting a step in Interact
    /// means this, not a switch to Autoplay (Chris, 2026-09-18: a tap
    /// after selecting a step stepped the play instead of the app).
    public func jump(to step: LabStep, flow: LabFlow) {
        let now = Date()
        tab = step.tabCase.demoTab
        menuOpen = false
        surface = nil
        asField = false
        fieldVoice = false
        byHold = false
        draft = ""
        script = nil
        askedAt = nil
        holding = false
        switch step.phase {
        case .rest, .ask:
            break
        case .menu, .askMenu:
            menuOpen = true
            menuAt = now
        case .field:
            open(.ask, asField: true)
            typed(step.line)
        case .surface:
            let item = step.item ?? .talk
            open(item)
            surfaceAt = now.addingTimeInterval(-1)
            let script = flow.script
            switch step.verb {
            case .idle, .listening:
                if item == .ask { typed(step.line) }
            default:
                // The ask is made; when, so the answer is at this state.
                self.script = script
                draft = script.ask
                let words = Double(script.answer.split(separator: " ").count)
                let t: Double
                switch step.verb {
                case .thinking: t = 0.2
                case .searching, .error: t = Self.thinking + 0.2
                case .speaking: t = Self.thinking + Self.searching + 0.2
                default: t = Self.thinking + Self.searching + words / 9 + 0.6
                }
                askedAt = now.addingTimeInterval(-t)
            }
        }
    }

    public func close() {
        surface = nil
        surfaceAt = Date()
        menuOpen = false
        askedAt = nil
        script = nil
        holding = false
    }
}

extension LabScript {
    /// The script an ask is closest to, by its words.
    static func matching(_ text: String) -> LabScript? {
        let t = text.lowercased()
        func has(_ words: String...) -> Bool { words.contains { t.contains($0) } }
        if has("arm", "secure", "lock up", "away mode") { return all.first { $0.id == "arm" } }
        if has("light", "dim", "patio", "lamp", "bright") { return all.first { $0.id == "patio" } }
        if has("package", "deliver", "amazon", "front door") { return all.first { $0.id == "packages" } }
        if has("offline", "camera keeps", "disconnect", "drops") { return all.first { $0.id == "offline" } }
        if has("sensor", "where should", "place", "put the") { return all.first { $0.id == "placement" } }
        if has("phone") { return all.first { $0.id == "power" } }
        if has("battery", "charge", "last") { return all.first { $0.id == "battery" } }
        return nil
    }
}

/// What a conversation can do when it's live rather than played.
struct LabConversationActions {
    var draft: Binding<String>
    var submit: (String) -> Void
    var close: () -> Void
    var toggleVoice: () -> Void = {}
}

struct LabConversationActionsKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: LabConversationActions? = nil
}

extension EnvironmentValues {
    var labConversationActions: LabConversationActions? {
        get { self[LabConversationActionsKey.self] }
        set { self[LabConversationActionsKey.self] = newValue }
    }
}

// MARK: - The stage

/// The phone, live: the app's screens with the pod in the tab bar, the
/// spec's menu, its surfaces and looks, driven by you.
struct LabAppView: View {
    let frame: LabFrame
    @ObservedObject var config: RingConfig
    @ObservedObject var session: LabAppSession = .shared
    @ObservedObject var home: QuidgetDemo = .shared

    var body: some View {
        let spec = frame.spec
        let now = Date()
        let phone = LabMorphView.phone
        let defaultScript = LabScript.named(Int(frame.p("voiceAsk", .system)))
        let transcript = frame.transcribing && !frame.transcript.isEmpty ? frame.transcript.map(\.text).joined(separator: " ") : nil
        let conversation = session.conversation(at: now, defaultScript: defaultScript, transcript: transcript)
        let item = session.surface
        let verb = conversation?.verb ?? .idle
        let surface: LabSurfaceSpec = {
            guard let item else { return LabSurfaceSpec(kind: .pod) }
            var s = spec.resolvedSurface(for: item)
            if session.byHold, spec.longPress.isFullScreen { s.kind = .fullScreen }
            // The field is a pill until the ask is sent.
            if session.showingField { s.kind = .pill }
            return s
        }()
        let state = surface.morphState
        let look = spec.resolvedLook(for: verb)
        let panelFrame = frame.applying(look, config: config).applying(surface)
        let age = now.timeIntervalSince(session.surfaceAt)
        let spring = Animation.spring(response: 0.5, dampingFraction: 0.8)
        let home = LabMorphView.home(of: state.kind)
        let podHome = LabMorphView.home(of: .pod)
        // On the Nexus tab the pod is the agent; elsewhere the spec's
        // Ask button is, where it puts it.
        let placement: LabAskPlacement = session.tab == .dashboard ? .tabBar : (spec.askPlacement ?? .floating)
        let askHome = placement == .tabBar ? podHome : LabAskButton.home(placement, size: phone)
        let actions = LabConversationActions(
            draft: Binding(get: { session.draft }, set: { session.typed($0) }),
            submit: { session.submit($0, defaultScript: defaultScript) },
            close: { session.close() },
            toggleVoice: { session.toggleVoice() })
        let menuSince = now.timeIntervalSince(session.menuAt)

        return ZStack {
            // The app, for real: tabs switch, the arm bar arms.
            NexusScreen(tab: NexusTab(session.tab), home: self.home, size: phone, showsTabBar: false)
            // The dim under a surface closes it.
            Color.black.opacity(state.kind == .sheet ? 0.4 : state.kind == .fullScreen ? state.dim : state.kind == .pod ? 0 : 0.15)
                .contentShape(Rectangle())
                .allowsHitTesting(state.kind != .pod)
                .onTapGesture { session.close() }
                .animation(spring, value: state.kind)
            VStack {
                Spacer()
                TabBarPreview(config: config, selectedTab: $session.tab, width: phone.width - LabPhone.inset * 2, hidesPodContent: true)
                    .padding(.bottom, LabPhone.bottom)
                    .opacity(state.kind == .fullScreen ? 0 : 1)
                    .allowsHitTesting(state.kind == .pod)
                    .animation(spring, value: state.kind)
            }
            if spec.tap == .menu || spec.longPress == .menu {
                LabGooeyMenu(frame: frame.applying(spec.action, config: config),
                             center: askHome,
                             open: session.menuOpen, since: menuSince,
                             icons: spec.items.map(\.symbol), drawsButton: false,
                             onSelect: { session.choose(spec.items[$0]) })
                    .opacity(state.kind == .pod ? 1 : 0)
                    .animation(spring, value: state.kind)
            }
            if placement != .tabBar {
                let askFrame = frame.applying(spec.ask ?? spec.action, config: config).applying(spec.resolvedLook(for: .idle), config: config)
                LabAskButton(frame: askFrame, config: config, size: phone, placement: placement, style: spec.askStyle ?? .goo,
                             open: session.menuOpen, since: menuSince, items: spec.items,
                             suggestions: (spec.askOffers ?? .actions) == .suggestions && session.tab == .devices ? LabAskContext.devices : [])
                    .allowsHitTesting(false)
                    .opacity(state.kind == .pod ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: session.tab)
            }
            // The pod (or the Ask button): tap, and hold.
            Circle().fill(Color.clear)
                .frame(width: 64, height: 64)
                .contentShape(Circle())
                .position(askHome)
                .modifier(LabPodPress(
                    onTap: { session.tapPod(spec: spec) },
                    onHoldBegin: { session.beginHold(spec: spec) },
                    onHoldEnd: { session.endHold(transcript: transcript, defaultScript: defaultScript) }))
                .allowsHitTesting(state.kind == .pod)
            // The keyboard under a floating container, as in the play — on
            // the Mac; a phone brings its own.
            #if os(iOS)
            let keyboardUp = false
            #else
            let keyboardUp = conversation?.typing != nil && (state.kind == .pill || state.kind == .card || state.kind == .sheet)
            #endif
            let (lift, sheetHeight) = LabPlayView.keyboardFit(kind: state.kind, up: keyboardUp, phone: phone)
            ZStack(alignment: .bottom) {
                Color.clear
                if let t = conversation?.typing, keyboardUp {
                    LabKeyboardView(text: session.draft, typed: t.typed, phase: t.phase, width: phone.width)
                        .transition(.move(edge: .bottom))
                }
            }
            .allowsHitTesting(false)
            .animation(spring, value: keyboardUp)
            LabMorphPanel(state: state, frame: panelFrame, config: config,
                          sinceChange: state.kind == .pod ? .infinity : age,
                          untilChange: .infinity,
                          caption: verb.caption,
                          conversation: conversation,
                          height: sheetHeight)
                .environment(\.labConversationActions, actions)
                .position(home)
                .offset(y: -lift)
                .animation(spring, value: state.kind)
                .animation(spring, value: keyboardUp)
                .allowsHitTesting(state.kind != .pod)
        }
        .frame(width: phone.width, height: phone.height)
        .clipShape(RoundedRectangle(cornerRadius: AnimationExporter.phoneScreenCornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AnimationExporter.phoneScreenCornerRadius, style: .continuous).strokeBorder(Color.white.opacity(frame.screen == nil ? 0.15 : 0), lineWidth: 1))
    }
}

/// Tap, or press and hold: down starts the hold after 0.4 s; a lift
/// before that is a tap.
struct LabPodPress: ViewModifier {
    let onTap: () -> Void
    let onHoldBegin: () -> Void
    let onHoldEnd: () -> Void
    @State private var down: Date? = nil
    @State private var held = false
    @State private var timer: Task<Void, Never>? = nil

    func body(content: Content) -> some View {
        content.gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard down == nil else { return }
                down = Date()
                held = false
                timer = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled, down != nil else { return }
                    held = true
                    onHoldBegin()
                }
            }
            .onEnded { _ in
                timer?.cancel()
                if held { onHoldEnd() } else { onTap() }
                down = nil
                held = false
            })
    }
}
