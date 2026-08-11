import Foundation
import Combine
import SwiftUI

/// Which side of the conversation the pill is currently illustrating.
public enum VoicePillMode: Equatable {
    case listening
    case speaking
}

/// One turn in the conversation, shown as a Messages-app-style bubble in
/// `VoicePillView`. `text` is `var` (not `let`) so an in-progress agent
/// reply — which can arrive as several progressively-longer deltas, see
/// `ElevenLabsVoiceService`'s `agent_chat_response_part` handling — can
/// update the same bubble in place instead of appending a new one per chunk.
public struct VoiceMessage: Identifiable, Equatable {
    public enum Role: Equatable {
        case user
        case agent
    }

    public let id = UUID()
    public let role: Role
    public var text: String
}

/// Orchestrates the hands-free loop between `SpeechToTextService` (mic →
/// text) and `ElevenLabsVoiceService` (text → agent speech): listen for an
/// utterance, send it, wait for the agent's reply to finish, listen again.
/// Started/stopped from one place — `RingConfig.init()` wires
/// `setActive(_:)` to `voiceReactiveEnabled && elevenLabs.connectionState
/// == .connected` — so it's always in sync regardless of which views
/// happen to be on screen.
///
/// `VoicePillView` (in the `RingAnimator` target) reads `isVisible`,
/// `mode`, `messages`, and `level` directly to render the "listening"/
/// "speaking" pill above the tab bar in the phone mockup; nothing here is
/// UI-specific.
/// `@unchecked Sendable`: same reasoning as `SpeechToTextService`/
/// `ElevenLabsVoiceService`/`AudioLevelMonitor` — the demo-mode
/// `DispatchQueue.main.asyncAfter` callback in `handleFinalTranscript`
/// captures `self` in a `@Sendable` closure, which requires this type to
/// be `Sendable`. Every mutation stays on the main thread already (all
/// callers — Combine sinks on `@Published` sources, `stt.onFinalTranscript`,
/// `elevenLabs.onResponseComplete`, and this `.main`-targeted
/// `asyncAfter` — run on main), so this is safe.
public final class VoiceConversationController: ObservableObject, @unchecked Sendable {
    @Published public private(set) var isVisible = false
    @Published public private(set) var mode: VoicePillMode = .listening
    /// Live partial transcript while listening — what's about to become the
    /// next `.user` message in `messages` once the utterance finishes.
    @Published public private(set) var caption: String = ""
    /// The back-and-forth so far, oldest first — `VoicePillView` renders
    /// these as chat bubbles. Cleared each time the loop restarts
    /// (`setActive(true)`), not on every utterance, so a whole exchange
    /// stays visible rather than just the latest line.
    @Published public private(set) var messages: [VoiceMessage] = []
    /// Waveform amplitude for whichever side is currently active — the
    /// mic while listening, the agent's decoded speech while speaking.
    @Published public private(set) var level: Double = 0

    public let stt = SpeechToTextService()
    private let elevenLabs: ElevenLabsVoiceService
    private var active = false
    /// TEMPORARY demo flag (see `RingConfig.voiceDemoModeEnabled`) — when
    /// true, `handleFinalTranscript` just displays what it heard instead of
    /// sending it to ElevenLabs, so the listen → transcribe → pill pipeline
    /// can be shown off without a live agent connection.
    private var demoMode = false
    private var cancellables = Set<AnyCancellable>()
    /// Pending "start listening" work scheduled by `beginGreetingWindow()`
    /// — cancelled by `handleAgentTurnStarted()` if the agent starts an
    /// unprompted greeting before it fires.
    private var greetingGraceWorkItem: DispatchWorkItem?
    /// How long to wait, right when the loop activates, before opening the
    /// mic — long enough for a proactive agent greeting to announce itself
    /// via `onAgentTurnStarted` first.
    private let greetingGraceInterval: TimeInterval = 0.6

    public init(elevenLabs: ElevenLabsVoiceService) {
        self.elevenLabs = elevenLabs

        stt.$partialTranscript
            .sink { [weak self] text in
                guard let self, self.mode == .listening else { return }
                self.caption = text
                // Live-fills the trailing "…" bubble `beginListening()`
                // seeds as words are actually recognized, rather than only
                // showing anything once the whole utterance is finished.
                guard !text.isEmpty else { return }
                self.updateOrAppendMessage(role: .user, text: text)
            }
            .store(in: &cancellables)

        stt.$level
            .sink { [weak self] level in
                guard let self, self.mode == .listening else { return }
                self.level = level
            }
            .store(in: &cancellables)

        elevenLabs.$level
            .sink { [weak self] level in
                guard let self, self.mode == .speaking else { return }
                self.level = level
            }
            .store(in: &cancellables)

        elevenLabs.$lastAgentResponse
            .sink { [weak self] text in
                guard let self, self.active, !text.isEmpty else { return }
                self.mode = .speaking
                // Animated explicitly at the mutation itself, rather than
                // relying only on `VoicePillView`'s `.animation(value:
                // messages.count)` — that only covers a *new* bubble
                // appearing, not this same bubble's *later* deltas growing
                // it further. `withAnimation` here means every delta —
                // first word through last — animates the resize, which
                // (since the pod is bottom-anchored above the tab bar) is
                // what makes it read as expanding upward one row at a time
                // instead of popping to each new size.
                withAnimation(.bouncy(duration: 0.32, extraBounce: 0.05)) {
                    self.updateOrAppendMessage(role: .agent, text: text)
                }
            }
            .store(in: &cancellables)

        stt.onFinalTranscript = { [weak self] text in
            self?.handleFinalTranscript(text)
        }

        elevenLabs.onResponseComplete = { [weak self] in
            self?.resumeListening()
        }

        elevenLabs.onAgentTurnStarted = { [weak self] in
            self?.handleAgentTurnStarted()
        }
    }

    /// Call whenever the conditions that should drive this
    /// (`RingConfig.voiceReactiveEnabled`, a live ElevenLabs connection, or
    /// `voiceDemoModeEnabled`) change. Idempotent — safe to call with the
    /// same values repeatedly.
    public func setActive(_ shouldBeActive: Bool, demo: Bool = false) {
        demoMode = demo
        guard shouldBeActive != active else { return }
        active = shouldBeActive
        if active {
            isVisible = true
            messages = []
            beginGreetingWindow()
        } else {
            greetingGraceWorkItem?.cancel()
            greetingGraceWorkItem = nil
            stt.stop()
            isVisible = false
            level = 0
            caption = ""
        }
    }

    /// Some agents are configured to speak first, right after connecting —
    /// starting the mic immediately here used to race that greeting and
    /// pick it up through the speaker, which the agent then heard back and
    /// replied to (talking to itself). Instead, wait briefly for
    /// `handleAgentTurnStarted()` to say the agent got there first; only
    /// open the mic here if nothing did by the time this fires.
    private func beginGreetingWindow() {
        mode = .listening
        caption = ""
        let work = DispatchWorkItem { [weak self] in
            self?.beginListening()
        }
        greetingGraceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + greetingGraceInterval, execute: work)
    }

    private func beginListening() {
        mode = .listening
        caption = ""
        // A "…" placeholder bubble right away, so listening reads as "go
        // ahead" from the first instant rather than showing nothing until
        // an utterance finishes — `stt.$partialTranscript`'s sink above
        // fills this in live as words are recognized.
        updateOrAppendMessage(role: .user, text: "…")
        stt.start()
    }

    private func resumeListening() {
        guard active else { return }
        beginListening()
    }

    /// The agent started talking without us sending anything first — cancel
    /// the greeting-window timer if it hasn't fired yet, and if the mic
    /// already happens to be live (the timer *just* fired, or this is a
    /// genuine agent interruption), stop listening immediately rather than
    /// let it keep capturing audio while the agent is mid-sentence.
    private func handleAgentTurnStarted() {
        greetingGraceWorkItem?.cancel()
        greetingGraceWorkItem = nil
        if mode == .listening {
            stt.stop()
        }
        mode = .speaking
    }

    private func handleFinalTranscript(_ text: String) {
        guard active else { return }
        // Settles the live "…"/partial-text bubble onto its final wording
        // (it's already a `.user` bubble from `beginListening()` /
        // `stt.$partialTranscript`, so this updates it in place rather than
        // appending a duplicate).
        updateOrAppendMessage(role: .user, text: text)
        if demoMode {
            // No real agent to reply to — just hold what we heard on
            // screen for a moment (still the "listening" visual state,
            // since there's no real speaking side in demo mode), then
            // listen for the next thing.
            caption = text
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
                self?.resumeListening()
            }
        } else {
            elevenLabs.sendUserMessage(text)
            mode = .speaking
            caption = text
            // Immediate "thinking" placeholder — `elevenLabs.$lastAgentResponse`'s
            // sink above fills this in for real once a reply actually starts
            // arriving, same as the user's own "…" bubble. Animated for the
            // same reason as that sink's update — consistent motion from
            // the very first placeholder through every later delta.
            withAnimation(.bouncy(duration: 0.32, extraBounce: 0.05)) {
                updateOrAppendMessage(role: .agent, text: "…")
            }
        }
    }

    /// Updates the trailing bubble in place if it's already the given role
    /// (the common case for both sides — an utterance fills in over several
    /// partial-transcript updates, an agent reply arrives as several
    /// progressively-longer chunks), otherwise starts a new one.
    private func updateOrAppendMessage(role: VoiceMessage.Role, text: String) {
        if let last = messages.last, last.role == role {
            messages[messages.count - 1].text = text
        } else {
            messages.append(VoiceMessage(role: role, text: text))
        }
    }
}
