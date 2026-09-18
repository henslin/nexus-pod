import SwiftUI

// The flow: Q Branch's document.
//
// Chris, 2026-09-18, on the step strip under the phone: "the bottom bar
// should become the right panel. Then you can build, from top to bottom,
// the different states that can be interacted with / autoplayed, and add
// steps or states to fully realize a flow or use case."
//
// Until then the steps were *derived* from the spec — tap opens the menu,
// the menu's first item opens its surface, the surface runs the verbs —
// and the conversation was a fixed script picked by number. Now the
// steps are the document. Three nouns:
//
// - A **flow** is a use case, top to bottom: "Arm the house from Devices."
//   An ordered list of steps, and the kit they draw on.
// - A **step** is the whole surface at one moment: which screen, what's
//   showing (the pod, its menu, an action's container, the Ask button
//   elsewhere), the agent's state, what's said, what the reply carries,
//   what moves it on, and what it does to the house.
// - The **kit** is the reusable parts a step points at — `LabSpec`,
//   unchanged: the pod, a look per agent state, the Ask button, the menu,
//   a container per action. A step doesn't own a look; it *uses*
//   Listening, and the kit says what Listening is.
//
// Every spec that already exists opens as a flow — `LabFlow(spec:)`
// derives the same steps the play used to derive, with the script's
// lines on them — so nothing built so far is lost.

/// What a step shows.
public enum LabStepPhase: String, Codable, CaseIterable, Identifiable, Sendable {
    /// The pod at rest in the tab bar.
    case rest
    /// The pod's menu open.
    case menu
    /// An action's container open, with the agent in a state.
    case surface
    /// The app-wide Ask button on a screen that isn't the Nexus tab.
    case ask
    /// That button's menu open.
    case askMenu

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .rest: return "Pod"
        case .menu: return "Menu"
        case .surface: return "Surface"
        case .ask: return "Ask button"
        case .askMenu: return "Ask menu"
        }
    }
    public var symbol: String {
        switch self {
        case .rest: return "circle"
        case .menu: return "circle.grid.2x1"
        case .surface: return "rectangle.portrait"
        case .ask: return "sparkles"
        case .askMenu: return "sparkles.rectangle.stack"
        }
    }
}

/// What moves a step on.
public enum LabStepAdvance: String, Codable, CaseIterable, Identifiable, Sendable {
    case timer, tap, hold
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .timer: return "Timer"
        case .tap: return "Tap"
        case .hold: return "Hold"
        }
    }
}

/// One moment of a flow.
public struct LabStep: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var phase: LabStepPhase = .rest
    /// The app screen, as `NexusTab.rawValue`.
    public var tab: String = "dashboard"
    /// For `.surface`: which action's container.
    public var item: LabActionItem? = nil
    /// The agent's state. `.idle` at rest.
    public var verb: LabAgentVerb = .idle
    /// A container this step insists on; `nil` lets the kit decide.
    public var container: LabMorphKind? = nil
    /// What's said here: the person's ask when listening, the named work
    /// when searching, the agent's answer when speaking, the follow-ups
    /// when done (one per line).
    public var line: String = ""
    /// A quidget the reply carries, from speaking on.
    public var carries: QuidgetKind? = nil
    public var advance: LabStepAdvance = .timer
    /// Seconds the step holds on the clock.
    public var seconds: Double = 3
    /// The agent's hand on the house as this step is reached.
    public var effect: LabScriptEffect? = nil

    public init() {}
    public init(_ phase: LabStepPhase, tab: NexusTab = .dashboard, item: LabActionItem? = nil, verb: LabAgentVerb = .idle,
                line: String = "", carries: QuidgetKind? = nil, seconds: Double = 3, effect: LabScriptEffect? = nil) {
        self.phase = phase
        self.tab = tab.rawValue
        self.item = item
        self.verb = verb
        self.line = line
        self.carries = carries
        self.seconds = seconds
        self.effect = effect
    }

    private enum CodingKeys: String, CodingKey { case id, phase, tab, item, verb, container, line, carries, advance, seconds, effect }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        phase = (try? c.decodeIfPresent(LabStepPhase.self, forKey: .phase)) ?? .rest
        tab = try c.decodeIfPresent(String.self, forKey: .tab) ?? "dashboard"
        item = try? c.decodeIfPresent(LabActionItem.self, forKey: .item)
        verb = (try? c.decodeIfPresent(LabAgentVerb.self, forKey: .verb)) ?? .idle
        container = try? c.decodeIfPresent(LabMorphKind.self, forKey: .container)
        line = try c.decodeIfPresent(String.self, forKey: .line) ?? ""
        carries = try? c.decodeIfPresent(QuidgetKind.self, forKey: .carries)
        advance = (try? c.decodeIfPresent(LabStepAdvance.self, forKey: .advance)) ?? .timer
        seconds = try c.decodeIfPresent(Double.self, forKey: .seconds) ?? 3
        effect = try? c.decodeIfPresent(LabScriptEffect.self, forKey: .effect)
    }

    public var tabCase: NexusTab { NexusTab(rawValue: tab) ?? .dashboard }

    /// The step's name in the navigator: what's showing, and the state.
    public var title: String {
        switch phase {
        case .rest: return "Idle"
        case .menu: return "Menu"
        case .surface:
            let i = item ?? .talk
            let v = i == .ask && verb == .listening ? "Typing" : verb.label
            return "\(i.label) · \(v)"
        case .ask: return "Ask · \(tabCase.label)"
        case .askMenu: return "Ask · Menu"
        }
    }
    /// The state's glyph, or the phase's when there's no state to show.
    public var symbol: String { phase == .surface ? verb.symbol : phase.symbol }
    /// Whether the line means anything here.
    public var speaks: Bool { phase == .surface && [.listening, .searching, .speaking, .done, .error].contains(verb) }
}

/// A use case: the steps, and the kit they draw on.
public struct LabFlow: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String = "Untitled"
    public var kit: LabSpec = LabSpec()
    public var steps: [LabStep] = []

    public init() {}
    public init(name: String, kit: LabSpec, steps: [LabStep]) {
        self.name = name
        self.kit = kit
        self.steps = steps
    }

    /// A spec as a flow: the steps the play used to derive from it, with
    /// a script's lines on them. This is the migration — every board
    /// built so far opens as it played.
    public init(spec: LabSpec, script: LabScript = LabScript.named(4), withError: Bool = false) {
        name = spec.name
        kit = spec
        var out: [LabStep] = [LabStep(.rest)]
        let item: LabActionItem? = spec.tap.item ?? (spec.tap == .menu ? (spec.items.contains(.talk) ? .talk : spec.items.first) : nil)
        if spec.tap == .menu { out.append(LabStep(.menu)) }
        if let item {
            var verbs: [LabAgentVerb] = [.listening, .thinking, .searching, .speaking, .done]
            if withError { verbs.insert(.error, at: 3) }
            for verb in verbs {
                var s = LabStep(.surface, item: item, verb: verb)
                switch verb {
                case .listening: s.line = script.ask
                case .searching: s.line = script.checking
                case .speaking: s.line = script.answer; s.carries = script.quidget; s.effect = script.effect
                case .done: s.line = script.followUps.joined(separator: "\n"); s.carries = script.quidget
                case .error: s.line = "I couldn’t reach the doorbell."
                default: break
                }
                out.append(s)
            }
        }
        out.append(LabStep(.ask, tab: .devices))
        out.append(LabStep(.askMenu, tab: .devices))
        steps = out
    }

    private enum CodingKeys: String, CodingKey { case id, name, kit, steps }
    public init(from decoder: Decoder) throws {
        // A flow, or — pasted from an older build, or the phone — a bare
        // spec, which opens as the flow it would have played.
        if let c = try? decoder.container(keyedBy: CodingKeys.self), c.contains(.steps) || c.contains(.kit) {
            id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
            kit = try c.decodeIfPresent(LabSpec.self, forKey: .kit) ?? LabSpec()
            steps = try c.decodeIfPresent([LabStep].self, forKey: .steps) ?? []
            if steps.isEmpty { self = LabFlow(spec: kit) }
        } else {
            self = LabFlow(spec: try LabSpec(from: decoder))
        }
    }

    // MARK: The conversation the steps spell

    /// The steps as a script, for the conversation views: the ask is the
    /// first listening line, the work the searching line, the answer the
    /// speaking line, the follow-ups the done lines; the reply carries
    /// what the speaking step carries and does what it does.
    public var script: LabScript {
        func line(_ verb: LabAgentVerb) -> String? {
            steps.first { $0.phase == .surface && $0.verb == verb && !$0.line.isEmpty }?.line
        }
        let speaking = steps.first { $0.phase == .surface && $0.verb == .speaking }
        return LabScript(id: id.uuidString, title: name,
                         ask: line(.listening) ?? "",
                         checking: line(.searching) ?? "Working on it…",
                         answer: line(.speaking) ?? "",
                         followUps: (line(.done) ?? "").split(separator: "\n").map(String.init).filter { !$0.isEmpty },
                         quidget: speaking?.carries ?? steps.first { $0.carries != nil }?.carries,
                         effect: speaking?.effect ?? steps.first { $0.effect != nil }?.effect)
    }

    // MARK: The clock

    /// Seconds a step holds; never so short the clock can't land in it.
    public func duration(of step: LabStep) -> Double { max(step.seconds, 0.2) }
    /// The whole flow's length on the clock.
    public var total: Double { steps.reduce(0) { $0 + duration(of: $1) } }
    /// Where each step starts on the clock.
    public var starts: [Double] {
        var t = 0.0
        return steps.map { let s = t; t += duration(of: $0); return s }
    }

    /// The step the clock is in at a time, and how far into it.
    public func position(at time: Double) -> (index: Int, since: Double) {
        guard !steps.isEmpty, total > 0 else { return (0, 0) }
        let t = time.truncatingRemainder(dividingBy: total)
        var acc = 0.0
        for (i, s) in steps.enumerated() {
            let d = duration(of: s)
            if t < acc + d { return (i, t - acc) }
            acc += d
        }
        return (steps.count - 1, 0)
    }

    /// The first and last steps that show a surface — the conversation's
    /// span, for transitions that run from when it opened.
    public var surfaceRange: ClosedRange<Int>? {
        let idx = steps.indices.filter { steps[$0].phase == .surface }
        guard let a = idx.first, let b = idx.last else { return nil }
        return a...b
    }

    // MARK: Editing

    /// A new step after another — Keynote's model: a copy of the one
    /// before, to change one thing on.
    public mutating func addStep(after id: UUID?) -> UUID {
        var s = id.flatMap { i in steps.first { $0.id == i } } ?? steps.last ?? LabStep(.rest)
        s.id = UUID()
        if let id, let i = steps.firstIndex(where: { $0.id == id }) { steps.insert(s, at: i + 1) } else { steps.append(s) }
        return s.id
    }
    public mutating func remove(_ id: UUID) { steps.removeAll { $0.id == id } }
    public func index(of id: UUID?) -> Int? { id.flatMap { i in steps.firstIndex { $0.id == i } } }
}

extension LabScriptEffect: Codable {
    private enum CodingKeys: String, CodingKey { case arm, dim }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let m = try c.decodeIfPresent(String.self, forKey: .arm), let mode = SecurityMode(rawValue: m) { self = .arm(mode) }
        else if let d = try c.decodeIfPresent(Double.self, forKey: .dim) { self = .dim(d) }
        else { throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "no effect")) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .arm(let m): try c.encode(m.rawValue, forKey: .arm)
        case .dim(let d): try c.encode(d, forKey: .dim)
        }
    }
    public var label: String {
        switch self {
        case .arm(let m): return "Arm · \(m.label)"
        case .dim(let d): return "Dim to \(Int((d * 100).rounded()))%"
        }
    }
}

// MARK: - Starters

extension LabFlow {
    /// The starters, as flows: each kit with the use case it was built
    /// to show.
    public static var starters: [LabFlow] {
        [LabFlow(spec: .theirKit, script: LabScript.named(5)),
         LabFlow(spec: .glassAndLight, script: LabScript.named(4)),
         LabFlow(spec: .water, script: LabScript.named(6))]
    }
}

// MARK: - Store

/// Flows saved by name, and the working one autosaved — the same shape
/// `LabSpecStore` had. Specs saved under the old keys are read once and
/// become flows.
@MainActor
public final class LabFlowStore: ObservableObject {
    @Published public private(set) var flows: [LabFlow] = []
    private static let key = "nexus.lab.flows"
    private static let currentKey = "nexus.lab.flow.current"

    public init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([LabFlow].self, from: data) { flows = decoded }
        else if let data = UserDefaults.standard.data(forKey: "nexus.lab.specs"),
                let specs = try? JSONDecoder().decode([LabSpec].self, from: data) {
            flows = specs.map { LabFlow(spec: $0) }
            persist()
        }
    }

    /// The working flow — or the spec that was working before flows
    /// existed, as one — or, first time, a starter.
    public static func loadCurrent() -> LabFlow {
        if let data = UserDefaults.standard.data(forKey: currentKey),
           let flow = try? JSONDecoder().decode(LabFlow.self, from: data) { return flow }
        let spec = LabSpecStore.loadCurrent()
        return LabFlow(spec: spec, script: LabScript.named(spec.name == LabSpec.theirKit.name ? 5 : 4))
    }
    public static func autosave(_ flow: LabFlow) {
        if let data = try? JSONEncoder().encode(flow) { UserDefaults.standard.set(data, forKey: currentKey) }
        LabSpecStore.autosave(flow.kit)
    }

    public func save(_ flow: LabFlow) {
        flows.removeAll { $0.id == flow.id || $0.name == flow.name }
        flows.append(flow)
        persist()
    }
    public func delete(_ flow: LabFlow) {
        flows.removeAll { $0.id == flow.id }
        persist()
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(flows) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    public static func json(_ flow: LabFlow) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(flow)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
    /// A flow — or a bare spec, which becomes one — from JSON.
    public static func flow(fromJSON text: String) -> LabFlow? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(LabFlow.self, from: data)
    }
    public static func copy(_ flow: LabFlow) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json(flow), forType: .string)
        #else
        UIPasteboard.general.string = json(flow)
        #endif
    }
    public static func paste() -> LabFlow? {
        #if canImport(AppKit)
        return NSPasteboard.general.string(forType: .string).flatMap(flow(fromJSON:))
        #else
        return UIPasteboard.general.string.flatMap(flow(fromJSON:))
        #endif
    }
}

// MARK: - Selection in the navigator

/// What Q Branch's inspector is looking at: the flow, its kit, or one
/// step.
public enum LabQSelection: Hashable, Sendable {
    case flow, kit
    case step(UUID)
}
