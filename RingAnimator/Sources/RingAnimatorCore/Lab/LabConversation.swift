import SwiftUI

// The conversation inside a surface — what the agent is *for*.
//
// Chris, overnight 2026-09-15/16: "You may want to use it for a quick
// question, for device help, onboarding and placement. You might not be
// getting great battery life… What makes working with you work well?"
//
// What makes it work: you see it heard you (the ask, echoed, word by
// word); you see it working (a state, named, not a spinner); the answer
// arrives as it is made, not after; it answers the question and then
// offers the next move as a tap, not a paragraph; and it never takes the
// screen unless you asked for the screen. The scripts below are four
// real asks; the play runs them through the states with the assigned
// looks, in text or in voice, so a surface is judged on a conversation
// rather than on placeholder copy.

/// One scenario: the ask, what the agent does about it, the answer, and
/// the follow-ups it offers.
public struct LabScript: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var ask: String
    /// The named work in the Searching state — "Checking the doorbell…".
    public var checking: String
    public var answer: String
    public var followUps: [String]
    /// A quidget the reply carries — the thing you asked about, as a
    /// control, so you never ask twice to get a setting right.
    public var quidget: QuidgetKind? = nil

    public static let all: [LabScript] = [
        LabScript(id: "battery", title: "Quick question",
                  ask: "How long will the doorbell battery last?",
                  checking: "Checking the doorbell…",
                  answer: "About three weeks at this rate. It’s at 62% and drains fastest during Live View. Lowering motion sensitivity would stretch it to a month.",
                  followUps: ["Lower it", "Battery history", "Remind me at 20%"]),
        LabScript(id: "offline", title: "Device help",
                  ask: "The front camera keeps going offline.",
                  checking: "Reading the camera’s log…",
                  answer: "It drops every night around 2 AM — that’s when your router reboots. Moving it to the 2.4 GHz band reaches the porch better and rides through the reboot.",
                  followUps: ["Move it", "Why 2.4 GHz?", "Show signal"]),
        LabScript(id: "placement", title: "Onboarding & placement",
                  ask: "Where should I put the motion sensor?",
                  checking: "Looking at the hallway…",
                  answer: "Waist height on the wall facing the door, not the ceiling, and away from the heating vent. That covers the whole hall without catching the cat.",
                  followUps: ["Show me the spot", "What about pets?", "Later"]),
        LabScript(id: "power", title: "Battery life",
                  ask: "My phone battery has been bad lately.",
                  checking: "Checking what the app used…",
                  answer: "Nexus used 9% today, nearly all of it Live View on the doorbell. Turning off background refresh for the Feed saves most of that without missing an alert.",
                  followUps: ["Turn it off", "Show usage", "Not now"]),
        LabScript(id: "patio", title: "Dim the patio light",
                  ask: "Dim the Patio Light",
                  checking: "Dimming the patio light…",
                  answer: "I’ve dimmed the lights to 40%.",
                  followUps: [], quidget: .light),
        LabScript(id: "arm", title: "Arm the house",
                  ask: "Arm my system",
                  checking: "Arming the cameras…",
                  answer: "Your cameras are armed and your system is in Arm Away mode.",
                  followUps: ["Arm Away when you leave?", "Disarm when you arrive home?"], quidget: .security),
        LabScript(id: "packages", title: "Packages today",
                  ask: "Did I receive any packages today?",
                  checking: "Checking the front door…",
                  answer: "You received a package from Amazon at 2:15PM.",
                  followUps: [], quidget: .clip),
    ]

    public static func named(_ index: Int) -> LabScript { all[max(0, min(all.count - 1, index))] }
}

/// Where a conversation is: which script, in which mode, in which
/// state, for how long.
public struct LabConversation: Equatable {
    public enum Mode: Equatable, Sendable { case text, voice }
    public var script: LabScript
    public var mode: Mode
    public var verb: LabAgentVerb
    /// Seconds in this verb.
    public var since: Double
    /// Seconds since the surface opened — for parts that persist across
    /// verbs (the ask, once made).
    public var age: Double

    public init(script: LabScript, mode: Mode, verb: LabAgentVerb, since: Double, age: Double) {
        self.script = script
        self.mode = mode
        self.verb = verb
        self.since = since
        self.age = age
    }

    /// The ask so far: typed at ~14 characters a second, or spoken at
    /// ~3 words a second — or, with the transcript live, your own words.
    public func askShown(frame: LabFrame) -> String {
        switch verb {
        case .idle: return ""
        case .listening:
            if mode == .voice, frame.transcribing, !frame.transcript.isEmpty {
                return frame.transcript.suffix(14).map(\.text).joined(separator: " ")
            }
            // A beat before the first character or word, so the empty
            // surface (and its suggestions) is seen.
            if mode == .text {
                let n = Int(max(0, since - 0.9) * 14)
                return String(script.ask.prefix(n))
            }
            let words = script.ask.split(separator: " ")
            return since < 0.6 ? "" : words.prefix(Int((since - 0.6) * 3) + 1).joined(separator: " ")
        default:
            if mode == .voice, frame.transcribing, !frame.transcript.isEmpty {
                return frame.transcript.suffix(14).map(\.text).joined(separator: " ")
            }
            return script.ask
        }
    }
    /// Whether the ask is still being made.
    public var composing: Bool { verb == .listening }
    /// The status line — the state, named.
    public var status: String? {
        switch verb {
        case .thinking: return "Thinking…"
        case .searching: return script.checking
        case .error: return "I couldn’t reach the doorbell — trying again."
        default: return nil
        }
    }
    /// How much of the answer has arrived, in seconds of streaming.
    public var answerElapsed: Double {
        switch verb {
        case .speaking: return since
        case .done: return .infinity
        default: return 0
        }
    }
    public var showsFollowUps: Bool { verb == .done }
}

// MARK: - Streaming words

/// Words arriving over time — each one blurred and bright for an
/// instant, then settled. The transcript's arrival, used for the answer.
struct LabStreamWords: View {
    let text: String
    let elapsed: Double
    var rate: Double = 9
    var size: Double = 17
    var weight: Font.Weight = .regular
    var color: Color = .primary
    var glow: Color = .clear
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        let words = text.split(separator: " ").map(String.init)
        let shown = elapsed.isFinite ? min(words.count, Int(elapsed * rate)) : words.count
        LabWrap(spacing: 5, alignment: alignment) {
            ForEach(Array(words.prefix(shown).enumerated()), id: \.offset) { i, w in
                let age = elapsed.isFinite ? elapsed - Double(i) / rate : .infinity
                let isNew = age < 0.3
                Text(w)
                    .font(.system(size: size, weight: weight))
                    .foregroundStyle(color)
                    .opacity(min(1, max(0, age * 6 + 0.1)))
                    .blur(radius: isNew ? (0.3 - age) * 14 : 0)
                    .shadow(color: isNew ? glow : .clear, radius: 8)
            }
        }
        .animation(.easeOut(duration: 0.2), value: shown)
    }
}

// MARK: - The conversation in a surface

/// The conversation laid out for a surface's shape. The hero rides in
/// each (the assigned look, in the verb's state); the rest is the
/// exchange: the ask, the status, the answer, the follow-ups, the input.
struct LabConversationView: View {
    let kind: LabMorphKind
    let conversation: LabConversation
    let frame: LabFrame
    @ObservedObject var config: RingConfig
    let size: CGSize
    var heroScale: Double = 0.42
    @StateObject private var quidgets = QuidgetDemo()
    @Namespace private var quidgetNS

    private var c: LabConversation { conversation }
    /// The reply's quidget, once the answer has landed — if the spec
    /// lets the agent reply with that kind.
    private var quidget: QuidgetKind? {
        guard c.verb == .done, let q = c.script.quidget, frame.spec.quidgetKinds.contains(q) else { return nil }
        return q
    }
    private var primary: Color { frame.colors.first ?? .accentColor }

    var body: some View {
        switch kind {
        case .pod:
            LabHeroView(frame: frame, config: config, diameter: 62)
        case .pill:
            HStack(spacing: 10) {
                LabHeroView(frame: frame, config: config, diameter: 44)
                Text(c.status ?? (c.composing ? c.askShown(frame: frame) : c.script.answer))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
        case .card:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    LabHeroView(frame: frame, config: config, diameter: 44)
                    Text(c.askShown(frame: frame))
                        .font(.headline)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                if let status = c.status {
                    Text(status).font(.subheadline).foregroundStyle(.secondary)
                } else if c.answerElapsed > 0 {
                    LabStreamWords(text: c.script.answer, elapsed: c.answerElapsed, size: 15, color: .secondary)
                        .lineLimit(3)
                }
                if c.showsFollowUps { followUps(size: 12) }
                Spacer(minLength: 0)
            }
            .padding(16)
        case .sheet:
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    LabHeroView(frame: frame, config: config, diameter: 44)
                    Text("Nexus").font(.title3.bold())
                    Spacer(minLength: 0)
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary).font(.title3)
                }
                // Before you've said anything: what you might ask, as
                // taps — the other scripts' asks stand in for context.
                let ask = c.askShown(frame: frame)
                if c.composing, ask.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Try asking").font(.caption).foregroundStyle(.secondary)
                        LabWrap(spacing: 6) {
                            ForEach(LabScript.all.filter { $0.id != c.script.id }, id: \.id) { other in
                                Text(other.ask)
                                    .font(.system(size: 13, weight: .medium))
                                    .padding(.horizontal, 11).padding(.vertical, 7)
                                    .background(Capsule().fill(.fill.tertiary))
                            }
                        }
                    }
                    .padding(.leading, 4)
                    .transition(.opacity)
                }
                // The ask, as a bubble on the right — yours.
                if !ask.isEmpty {
                    HStack {
                        Spacer(minLength: 40)
                        Text(ask + (c.composing && c.mode == .text ? "▍" : ""))
                            .font(.body)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(primary.opacity(0.2)))
                    }
                }
                // The agent's turn.
                if let status = c.status {
                    HStack(spacing: 8) {
                        Circle().fill(primary).frame(width: 6, height: 6)
                            .opacity(0.5 + 0.5 * sin(frame.time * 6))
                        Text(status).font(.subheadline).foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                    .padding(.leading, 4)
                } else if c.answerElapsed > 0 {
                    LabStreamWords(text: c.script.answer, elapsed: c.answerElapsed, size: 17, glow: primary.opacity(0.5))
                        .padding(.leading, 4)
                }
                if let quidget {
                    quidgetInline(quidget, medium: quidget == .clip || frame.spec.quidgetInlineSize == .medium)
                }
                if c.showsFollowUps { followUps(size: 13).padding(.leading, 4) }
                Spacer(minLength: 0)
                inputBar(height: 44)
            }
            .padding(20)
            .blur(radius: quidgets.expanded == nil ? 0 : 16)
            .overlay { QuidgetOverlay(demo: quidgets, namespace: quidgetNS, screen: size) }
        case .fullScreen:
            VStack(spacing: 16) {
                Spacer(minLength: 30)
                LabHeroView(frame: frame, config: config, diameter: size.width * heroScale)
                Text(c.status ?? (c.composing ? (c.mode == .voice ? "Listening…" : "Typing…") : c.verb == .speaking ? "Speaking" : c.verb == .done ? "Done" : ""))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                let ask = c.askShown(frame: frame)
                if !ask.isEmpty {
                    Text(ask)
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: size.width - 64)
                }
                if c.answerElapsed > 0 {
                    LabStreamWords(text: c.script.answer, elapsed: c.answerElapsed, rate: 6, size: 22, weight: .medium, glow: primary.opacity(0.6), alignment: .center)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: size.width - 56)
                }
                if let quidget {
                    quidgetInline(quidget, medium: quidget == .clip || frame.spec.quidgetInlineSize == .medium)
                }
                if c.showsFollowUps { followUps(size: 14, centered: true) }
                Spacer()
                if c.mode == .voice {
                    LabWaveformBars(frame: frame, bars: 28, height: 22).frame(height: 30)
                    Text(c.composing ? "Tap to send · hold to keep talking" : "Tap to interrupt")
                        .font(.caption).foregroundStyle(.tertiary)
                } else {
                    inputBar(height: 48).padding(.horizontal, 20)
                }
                Spacer().frame(height: 34)
            }
            .blur(radius: quidgets.expanded == nil ? 0 : 16)
            .overlay { QuidgetOverlay(demo: quidgets, namespace: quidgetNS, screen: size) }
        }
    }

    /// The quidget's place in the reply. It stays while the quidget is
    /// expanded over the container, and the quidget comes back to it.
    private func quidgetInline(_ kind: QuidgetKind, medium: Bool) -> some View {
        let s: QuidgetSize = medium ? .medium : .small
        let h: CGFloat = s == .small ? QuidgetView.smallSize.height : (kind == .clip ? 362 : 162)
        return ZStack(alignment: .leading) {
            Color.clear.frame(height: h)
            if quidgets.expanded != kind {
                QuidgetView(kind: kind, size: s, demo: quidgets, namespace: quidgetNS)
            }
        }
        .transition(.opacity)
    }

    /// The next move, as taps.
    private func followUps(size: Double, centered: Bool = false) -> some View {
        LabWrap(spacing: 6, alignment: centered ? .center : .leading) {
            ForEach(c.script.followUps, id: \.self) { f in
                Text(f)
                    .font(.system(size: size, weight: .medium))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(.fill.tertiary))
                    .overlay(Capsule().strokeBorder(primary.opacity(0.35)))
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    /// The text field, or the voice bar: where the ask goes in.
    private func inputBar(height: CGFloat) -> some View {
        HStack(spacing: 10) {
            Group {
                if c.mode == .voice {
                    LabWaveformBars(frame: frame, bars: 26, height: 20)
                } else {
                    HStack {
                        Text(c.composing ? c.askShown(frame: frame) : "Ask Nexus")
                            .foregroundStyle(c.composing ? .primary : .secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "mic.fill").foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                }
            }
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(.fill.tertiary))
            LabHeroView(frame: frame, config: config, diameter: height)
        }
    }
}
