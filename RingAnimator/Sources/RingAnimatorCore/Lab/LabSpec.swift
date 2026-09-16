import SwiftUI
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

// The System: the Lab's experiments assigned to the product's slots.
//
// Chris, 2026-09-15: "make this exploration into a system … make the orbs
// for the different states then be able to select them for the UI. Same
// with gooey buttons. Same with the interactions/sheets/fullscreen/long
// press." The Lab is the catalogue of ingredients; a `LabSpec` is the
// recipe — one look per slot the Nexus surface needs, a menu of actions,
// a surface per action, and what the two gestures do. `LabPlayView`
// plays the whole spec end to end; the board beside it shows every slot
// and its gaps. Specs save by name and travel as JSON, so the phone
// viewer can play what the Mac assembled.

// MARK: - The product's vocabulary

/// The states the agent moves through — the product's verbs, as opposed
/// to Libraries.dev's nine orb verbs (which are *looks* an orb can wear).
public enum LabAgentVerb: String, CaseIterable, Identifiable, Codable, Sendable {
    case idle, listening, thinking, searching, speaking, done, error
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .idle: return "Idle"
        case .listening: return "Listening"
        case .thinking: return "Thinking"
        case .searching: return "Searching"
        case .speaking: return "Speaking"
        case .done: return "Done"
        case .error: return "Error"
        }
    }
    /// What the surface says while in this state.
    public var caption: String {
        switch self {
        case .idle: return "Nexus"
        case .listening: return "Listening…"
        case .thinking: return "Thinking…"
        case .searching: return "Searching…"
        case .speaking: return "Speaking"
        case .done: return "Done"
        case .error: return "Something went wrong"
        }
    }
    public var symbol: String {
        switch self {
        case .idle: return "circle"
        case .listening: return "ear"
        case .thinking: return "brain"
        case .searching: return "magnifyingglass"
        case .speaking: return "waveform"
        case .done: return "checkmark.circle"
        case .error: return "exclamationmark.triangle"
        }
    }
    /// The nearest of Libraries.dev's nine orb verbs — see
    /// `LabExperiment.orbVerbs` — for "use their orb for every state".
    public var orbKitVerb: Int {
        switch self {
        case .idle: return 7        // Breathing
        case .listening: return 3   // Listening
        case .thinking: return 0    // Working
        case .searching: return 1   // Searching
        case .speaking: return 6    // Composing
        case .done: return 8        // Shaping
        case .error: return 5       // Weaving
        }
    }
}

/// What a tap on the pod can reveal — the agent's actions, as menu items.
public enum LabActionItem: String, CaseIterable, Identifiable, Codable, Sendable {
    case ask, talk, show, remind, photo
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .ask: return "Ask"
        case .talk: return "Talk"
        case .show: return "Show me"
        case .remind: return "Remind"
        case .photo: return "Photo"
        }
    }
    public var symbol: String {
        switch self {
        case .ask: return "text.bubble.fill"
        case .talk: return "mic.fill"
        case .show: return "camera.viewfinder"
        case .remind: return "bell.fill"
        case .photo: return "photo.fill"
        }
    }
    /// The surface this action opens when none has been assigned.
    public var defaultSurface: LabMorphKind {
        switch self {
        case .ask: return .sheet
        case .talk, .show: return .fullScreen
        case .remind, .photo: return .card
        }
    }
}

/// Where the app-wide Ask button lives on screens that aren't the
/// Nexus tab.
public enum LabAskPlacement: String, CaseIterable, Identifiable, Codable, Sendable {
    case floating, navBar, tabBar
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .floating: return "Floating, bottom right"
        case .navBar: return "Navigation bar"
        case .tabBar: return "The Nexus pod itself"
        }
    }
}

/// What a gesture on the pod does.
public enum LabGestureResult: String, CaseIterable, Identifiable, Codable, Sendable {
    case nothing, menu, ask, talk, show, remind, photo
    /// Talk, taking the whole screen whatever container Talk normally
    /// opens — the voice-forward hold (Chris, 2026-09-16).
    case fullScreen
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .nothing: return "Nothing"
        case .menu: return "Open the menu"
        case .fullScreen: return "Talk, full screen"
        default: return item.map { "Open \($0.label)" } ?? rawValue
        }
    }
    public var item: LabActionItem? { self == .fullScreen ? .talk : LabActionItem(rawValue: rawValue) }
    public var isFullScreen: Bool { self == .fullScreen }
}

// MARK: - A look, a surface, a spec

/// One experiment as tuned: its knobs, post stack, palette and the shared
/// knobs that change how it reads. What an orb slot holds. Captured from
/// the Lab's current state — "use this, as it is now, for Listening".
public struct LabLook: Codable, Equatable, Sendable {
    public var experiment: String
    public var values: [String: Double]
    public var post: [String]
    public var palette: String
    public var intensity: Double = 0.5
    public var speed: Double = 1
    public var fill: Double = 1
    public var glyph: String = ""

    public init(experiment: String, values: [String: Double] = [:], post: [String] = [], palette: String = LabPalette.nexus.rawValue) {
        self.experiment = experiment
        self.values = values
        self.post = post
        self.palette = palette
    }

    /// The Lab as it stands: the current experiment, its knobs, the post
    /// stack's knobs, the palette and the shared knobs.
    @MainActor
    public init(from lab: LabState, experiment e: LabExperiment? = nil) {
        let e = e ?? lab.experiment
        var values = lab.values.filter { $0.key.hasPrefix(e.id + ".") }
        for post in lab.activePost { for (k, v) in lab.values where k.hasPrefix(post.experiment.id + ".") { values[k] = v } }
        self.init(experiment: e.id, values: values, post: lab.activePost.map(\.rawValue), palette: lab.palette.rawValue)
        intensity = lab.intensity
        speed = lab.speed
        fill = lab.fill
        glyph = lab.glyph
    }

    public var experimentCase: LabExperiment? { LabExperiment(rawValue: experiment) }
    public var posts: [LabPostEffect] { post.compactMap(LabPostEffect.init(rawValue:)) }
    public var paletteCase: LabPalette { LabPalette(rawValue: palette) ?? .nexus }
    public var name: String { experimentCase?.name ?? experiment }
    /// "Thinking Orbs · Searching" — the orb's verb, when it is theirs.
    public var title: String {
        if experimentCase == .orbKit, let v = values["orbKit.state"], Int(v) < LabExperiment.orbVerbs.count {
            return "\(name) · \(LabExperiment.orbVerbs[Int(v)])"
        }
        return name
    }
}

/// A surface: the Morph state an action opens, with the Morph knobs it
/// was tuned with (spring, edge glow…).
public struct LabSurfaceSpec: Codable, Equatable, Sendable {
    public var kind: LabMorphKind
    public var adornments: [LabMorphAdornment] = []
    public var enter: LabMorphTransition = .fade
    public var exit: LabMorphTransition = .fade
    public var values: [String: Double] = [:]
    /// What fills the container behind the conversation — Bloom Field,
    /// or any orb scaled to fill. `nil` is the dim alone.
    public var backdrop: LabLook?
    /// Full screen: the hero's size as a fraction of the width, and the
    /// dim behind. Optional so older specs decode; see `morphState`.
    public var heroScale: Double?
    public var dim: Double?

    public init(kind: LabMorphKind) { self.kind = kind }

    @MainActor
    public init(_ state: LabMorphState, from lab: LabState) {
        kind = state.kind
        adornments = Array(state.adornments).sorted { $0.rawValue < $1.rawValue }
        enter = state.enter
        exit = state.exit
        values = lab.values.filter { $0.key.hasPrefix("morph.") }
    }

    public var morphState: LabMorphState {
        var s = LabMorphState(kind, Set(adornments))
        s.enter = enter
        s.exit = exit
        s.backdrop = backdrop
        if let heroScale { s.heroScale = heroScale }
        if let dim { s.dim = dim }
        return s
    }
}

/// One assignment across every slot. The product, specified.
public struct LabSpec: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name = "Untitled"
    /// What lives in the tab bar at rest.
    public var pod: LabLook?
    /// A look per agent verb, keyed by `LabAgentVerb.rawValue`.
    public var states: [String: LabLook] = [:]
    /// The menu a tap reveals — Gooey, as tuned.
    public var action: LabLook?
    /// The items in it, in order.
    public var items: [LabActionItem] = [.ask, .talk, .show]
    /// The surface each item opens, keyed by `LabActionItem.rawValue`.
    public var surfaces: [String: LabSurfaceSpec] = [:]
    public var tap: LabGestureResult = .menu
    public var longPress: LabGestureResult = .talk
    /// The app-wide Ask button — "Ask Siri everywhere" (Chris,
    /// 2026-09-15): Gooey as tuned, and where it sits on screens that
    /// aren't the Nexus tab.
    public var ask: LabLook?
    public var askPlacement: LabAskPlacement?
    public var askStyle: LabAskStyle?

    public init() {}

    public func look(for verb: LabAgentVerb) -> LabLook? { states[verb.rawValue] }
    public func surface(for item: LabActionItem) -> LabSurfaceSpec? { surfaces[item.rawValue] }
    /// The surface an item opens — assigned, or the item's default.
    public func resolvedSurface(for item: LabActionItem) -> LabSurfaceSpec {
        surface(for: item) ?? LabSurfaceSpec(kind: item.defaultSurface)
    }
    /// The look a verb wears in play — assigned, or the pod's, or the ring.
    public func resolvedLook(for verb: LabAgentVerb) -> LabLook? { look(for: verb) ?? pod }

    /// Whether a slot is filled.
    public func has(_ target: LabSlotTarget) -> Bool {
        switch target {
        case .pod: return pod != nil
        case .state(let v): return states[v.rawValue] != nil
        case .action: return action != nil
        case .ask: return ask != nil
        }
    }

    /// Slots filled, out of the slots the spec has.
    public var filled: Int {
        (pod == nil ? 0 : 1) + states.count + (ask == nil ? 0 : 1) + (action == nil ? 0 : 1) + items.filter { surfaces[$0.rawValue] != nil }.count
    }
    public var total: Int { 1 + LabAgentVerb.allCases.count + 2 + items.count }
}

// MARK: - Starters

extension LabSpec {
    /// Three whole agents to start from, so Q Branch is never a blank
    /// board: their kit; glass and light; water. Each is a real answer
    /// to the question, not a demo of a slot.
    public static let starters: [LabSpec] = [theirKit, glassAndLight, water]

    private static func look(_ e: LabExperiment, _ values: [String: Double] = [:], post: [LabPostEffect] = [], palette: LabPalette = .nexus) -> LabLook {
        var l = LabLook(experiment: e.id, values: values, post: post.map(\.rawValue), palette: palette.rawValue)
        l.fill = 1
        return l
    }
    private static func orb(_ verb: LabAgentVerb) -> LabLook { look(.orbKit, ["orbKit.state": Double(verb.orbKitVerb)]) }
    private static func surface(_ kind: LabMorphKind, _ adornments: [LabMorphAdornment], enter: LabMorphTransition = .fade) -> LabSurfaceSpec {
        var s = LabSurfaceSpec(kind: kind)
        s.adornments = adornments
        s.enter = enter
        return s
    }

    public static var theirKit: LabSpec {
        var s = LabSpec()
        s.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        s.name = "Their Kit"
        s.pod = orb(.idle)
        for v in LabAgentVerb.allCases { s.states[v.rawValue] = orb(v) }
        s.action = look(.gooey, ["gooey.effect": 1, "gooey.fill": 0])
        s.ask = look(.gooey, ["gooey.effect": 1, "gooey.fill": 0])
        s.askPlacement = .floating
        s.askStyle = .goo
        s.items = [.ask, .talk, .show]
        s.surfaces["ask"] = surface(.sheet, [.edgeGlow])
        s.surfaces["talk"] = surface(.fullScreen, [.edgeGlow, .waveform], enter: .flare)
        s.surfaces["show"] = surface(.fullScreen, [.edgeGlow])
        return s
    }

    public static var glassAndLight: LabSpec {
        var s = LabSpec()
        s.id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        s.name = "Glass & Light"
        s.pod = look(.aurora)
        s.states["idle"] = look(.aurora)
        s.states["listening"] = look(.liquidRing)
        s.states["thinking"] = look(.sphere, post: [.bloom])
        s.states["searching"] = look(.constellation)
        s.states["speaking"] = look(.orb, post: [.bloom])
        s.states["done"] = look(.frostOrb)
        s.states["error"] = look(.aurora, palette: .ember)
        s.action = look(.gooey, ["gooey.effect": 0, "gooey.fill": 1])
        s.ask = look(.gooey, ["gooey.effect": 0, "gooey.fill": 1])
        s.askPlacement = .navBar
        s.askStyle = .pill
        s.items = [.ask, .talk, .show]
        s.surfaces["ask"] = surface(.sheet, [.borderBeam])
        s.surfaces["talk"] = surface(.fullScreen, [.edgeGlow, .transcript], enter: .flare)
        s.surfaces["show"] = surface(.card, [.edgeGlow])
        return s
    }

    public static var water: LabSpec {
        var s = LabSpec()
        s.id = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        s.name = "Water"
        s.pod = look(.tide)
        s.states["idle"] = look(.tide)
        s.states["listening"] = look(.droplet)
        s.states["thinking"] = look(.pool)
        s.states["searching"] = look(.caustics)
        s.states["speaking"] = look(.jelly)
        s.states["done"] = look(.globe)
        s.states["error"] = look(.lava)
        s.action = look(.gooey, ["gooey.effect": 3, "gooey.fill": 2])
        s.ask = look(.gooey, ["gooey.effect": 3, "gooey.fill": 2])
        s.askPlacement = .floating
        s.askStyle = .bar
        s.items = [.ask, .talk]
        s.surfaces["ask"] = surface(.sheet, [.edgeGlow, .transcript])
        var talk = surface(.fullScreen, [.edgeGlow, .waveform])
        talk.backdrop = look(.sunflower)
        talk.heroScale = 0.34
        talk.dim = 0.7
        s.surfaces["talk"] = talk
        return s
    }
}

// MARK: - Store

/// Named specs in UserDefaults, and the working spec autosaved so the
/// board survives a relaunch. JSON in and out through the pasteboard is
/// how a spec reaches the phone viewer.
@MainActor
public final class LabSpecStore: ObservableObject {
    @Published public private(set) var specs: [LabSpec] = []
    private static let key = "nexus.lab.specs"
    private static let currentKey = "nexus.lab.spec.current"

    public init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([LabSpec].self, from: data) { specs = decoded }
    }

    /// The working spec — or, first time, a starter, so the board and
    /// the play have something to show.
    public static func loadCurrent() -> LabSpec {
        guard let data = UserDefaults.standard.data(forKey: currentKey),
              let spec = try? JSONDecoder().decode(LabSpec.self, from: data) else { return LabSpec.theirKit }
        return spec.filled == 0 && spec.name == "Untitled" ? LabSpec.theirKit : spec
    }
    public static func autosave(_ spec: LabSpec) {
        if let data = try? JSONEncoder().encode(spec) { UserDefaults.standard.set(data, forKey: currentKey) }
    }

    /// Save the working spec under its name, replacing a same-named one.
    public func save(_ spec: LabSpec) {
        specs.removeAll { $0.id == spec.id || $0.name == spec.name }
        specs.append(spec)
        persist()
    }
    public func delete(_ spec: LabSpec) {
        specs.removeAll { $0.id == spec.id }
        persist()
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(specs) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    public static func json(_ spec: LabSpec) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(spec)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
    public static func spec(fromJSON text: String) -> LabSpec? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(LabSpec.self, from: data)
    }

    /// The system pasteboard, both ways.
    public static func copy(_ spec: LabSpec) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json(spec), forType: .string)
        #else
        UIPasteboard.general.string = json(spec)
        #endif
    }
    public static func paste() -> LabSpec? {
        #if canImport(AppKit)
        return NSPasteboard.general.string(forType: .string).flatMap(spec(fromJSON:))
        #else
        return UIPasteboard.general.string.flatMap(spec(fromJSON:))
        #endif
    }
}

// MARK: - Choosing for a slot

/// A slot Q Branch sent you to the Lab to fill. While set, the rail
/// shows the errand and a "Use" button; using it assigns and returns.
public enum LabSlotTarget: Equatable, Sendable {
    case pod
    case state(LabAgentVerb)
    case action
    case ask

    public var label: String {
        switch self {
        case .pod: return "the Pod"
        case .state(let v): return v.label
        case .action: return "the Menu"
        case .ask: return "the Ask button"
        }
    }
    public var hint: String {
        switch self {
        case .pod, .state: return "Tune any orb, then Use. The knobs, post stack and palette come with it."
        case .action: return "Tune Gooey, then Use."
        case .ask: return "Tune the Ask Button — placement, style, and the goo — then Use."
        }
    }
    public func accepts(_ e: LabExperiment) -> Bool {
        switch self {
        case .pod, .state: return e.canBeHero
        case .action: return e == .gooey
        case .ask: return e == .gooey || e == .askButton
        }
    }
    /// Where to start looking.
    public var startingExperiment: LabExperiment {
        switch self {
        case .pod, .state: return .orbKit
        case .action: return .gooey
        case .ask: return .askButton
        }
    }
}

extension LabState {
    /// Go to the Lab to choose for a slot.
    public func choose(for target: LabSlotTarget) {
        self.target = target
        experiment = lastBench.flatMap { target.accepts($0) ? $0 : nil } ?? target.startingExperiment
    }
    /// Click the thing to change it (Chris, 2026-09-16): a filled slot
    /// opens on the bench as it is, with the errand set so Use puts it
    /// back; an empty one goes choosing.
    public func edit(_ look: LabLook?, for target: LabSlotTarget) {
        if let look, look.experimentCase != nil {
            open(look)
            self.target = target
        } else {
            choose(for: target)
        }
    }
    /// The current experiment into the target slot, and back to Q Branch.
    public func fulfilTarget() {
        guard let target, target.accepts(experiment) else { return }
        switch target {
        case .pod: useCurrentLookAsPod()
        case .state(let v): useCurrentLook(for: v)
        case .action: useCurrentGooeyAsAction()
        case .ask: useCurrentAskButton()
        }
        self.target = nil
        experiment = .system
    }
}

// MARK: - Assigning, from the Lab

extension LabState {
    /// The current experiment, as tuned, into a state slot.
    public func useCurrentLook(for verb: LabAgentVerb) {
        spec.states[verb.rawValue] = LabLook(from: self)
    }
    public func useCurrentLookAsPod() { spec.pod = LabLook(from: self) }
    /// Libraries.dev's orb in every state, each wearing the nearest of
    /// its nine verbs — and in the pod, breathing.
    public func useOrbKitForEveryState() {
        for verb in LabAgentVerb.allCases {
            var look = LabLook(from: self, experiment: .orbKit)
            look.values["orbKit.state"] = Double(verb.orbKitVerb)
            spec.states[verb.rawValue] = look
        }
        var pod = LabLook(from: self, experiment: .orbKit)
        pod.values["orbKit.state"] = Double(LabAgentVerb.idle.orbKitVerb)
        spec.pod = pod
    }
    /// The Ask Button lab's placement and style, with Gooey as tuned, as
    /// the app-wide Ask button.
    public func useCurrentAskButton() {
        spec.ask = LabLook(from: self, experiment: .gooey)
        if experiment == .askButton {
            spec.askPlacement = LabAskPlacement.allCases[min(2, Int(value(LabExperiment.askButton.parameters[0], of: .askButton)))]
            spec.askStyle = LabAskStyle.allCases[min(3, Int(value(LabExperiment.askButton.parameters[1], of: .askButton)))]
        }
    }
    /// Gooey, as tuned, as the pod's menu.
    public func useCurrentGooeyAsAction() { spec.action = LabLook(from: self, experiment: .gooey) }
    /// A Morph state, with the Morph knobs, as an action's surface.
    public func useMorphState(_ state: LabMorphState, for item: LabActionItem) {
        spec.surfaces[item.rawValue] = LabSurfaceSpec(state, from: self)
        if !spec.items.contains(item) { spec.items.append(item) }
    }
    public func toggleItem(_ item: LabActionItem) {
        if let i = spec.items.firstIndex(of: item) { spec.items.remove(at: i) } else { spec.items.append(item) }
    }

    /// Bring a look back to the bench: select its experiment and restore
    /// its knobs, so a slot can be re-tuned and re-assigned.
    public func open(_ look: LabLook) {
        guard let e = look.experimentCase else { return }
        experiment = e
        resetParameters(of: e)
        for (k, v) in look.values { values[k] = v }
        post = look.posts
        palette = look.paletteCase
        intensity = look.intensity
        speed = look.speed
        fill = look.fill
        glyph = look.glyph
    }
    public func open(_ surface: LabSurfaceSpec) {
        experiment = .morph
        for (k, v) in surface.values { values[k] = v }
        if !morphStates.contains(where: { $0.kind == surface.kind }) { morphStates.append(surface.morphState) }
    }
}

extension LabFrame {
    /// This frame wearing a look: the look's experiment as hero with its
    /// post stack, its knobs over the frame's, its palette, its shared
    /// knobs. The look's speed scales the clock.
    public func applying(_ look: LabLook?, config: RingConfig) -> LabFrame {
        guard let look else { return self }
        var f = self
        f.hero = look.experimentCase
        f.heroPost = look.posts
        for (k, v) in look.values { f.params[k] = v }
        if let colors = look.paletteCase.colors { f.colors = colors }
        else { f.colors = [config.primaryColor, config.secondaryColor] + config.additionalColors }
        f.intensity = look.intensity
        f.fill = look.fill
        f.glyph = look.glyph.isEmpty ? nil : look.glyph
        f.time = time * look.speed
        return f
    }
    /// The Morph knobs a surface was tuned with, over the frame's.
    public func applying(_ surface: LabSurfaceSpec) -> LabFrame {
        var f = self
        for (k, v) in surface.values { f.params[k] = v }
        return f
    }
}

extension LabFrame {
    /// For harnesses: this frame at a given tap count, so many seconds
    /// after the tap.
    public func withTaps(_ taps: Int, since: Double) -> LabFrame {
        var f = self
        f.taps = taps
        f.sinceTap = since
        return f
    }
}

extension LabFrame {
    /// The same frame at a fixed moment — a still.
    public func withTime(_ t: Double) -> LabFrame {
        var f = self
        f.time = t
        return f
    }
    /// For harnesses: knob values over the frame's.
    public func withParams(_ values: [String: Double]) -> LabFrame {
        var f = self
        for (k, v) in values { f.params[k] = v }
        return f
    }
}
