import Foundation
import AVFoundation

/// Connection lifecycle for the ElevenLabs Conversational AI WebSocket.
public enum ElevenLabsConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
}

/// A live connection to an ElevenLabs Conversational AI agent, so the ring
/// can react to what a *real* voice assistant sounds like instead of (or
/// alongside) the local microphone — see `AudioLevelMonitor` for that path.
///
/// This talks directly to ElevenLabs' documented WebSocket protocol
/// (`wss://api.elevenlabs.io/v1/convai/conversation`) with plain
/// `URLSessionWebSocketTask` — no ElevenLabs SDK dependency, since adding a
/// Swift Package dependency isn't practical to verify from this
/// environment. Reference: https://elevenlabs.io/docs/eleven-agents/api-reference/eleven-agents/websocket
///
/// Deliberately text-in, audio-out rather than full mic-streaming: you type
/// a message (`sendUserMessage`), the agent replies with real synthesized
/// speech over the socket, which this class both plays back and measures
/// the live level of to drive the ring. Full duplex (streaming your own mic
/// to the agent as `user_audio_chunk` events, the same way `AudioLevelMonitor`
/// taps the mic for the local-reactive path) would be the natural next step
/// if you want to actually talk to it rather than type.
///
/// Like `AudioLevelMonitor`, fails silently/visibly through `connectionState`
/// rather than crashing — a bad API key, unreachable agent, or dropped
/// socket just surfaces as `.error(...)` in the UI.
///
/// `@unchecked Sendable`: `URLSessionWebSocketTask`'s completion handlers
/// are `@Sendable` and not guaranteed to run on the main thread, so capturing
/// `self` across them requires this to be provably thread-safe under Swift
/// 6's strict concurrency checking. Every mutation of a `@Published`
/// property below is manually routed through `DispatchQueue.main.async`,
/// same pattern as `AudioLevelMonitor`.
public final class ElevenLabsVoiceService: ObservableObject, @unchecked Sendable {
    @Published public private(set) var connectionState: ElevenLabsConnectionState = .disconnected
    /// Live 0...1 amplitude of the agent's synthesized speech, decayed
    /// smoothly between audio chunks — the ElevenLabs equivalent of
    /// `AudioLevelMonitor.level`.
    @Published public private(set) var level: Double = 0
    @Published public private(set) var lastUserMessage: String = ""
    @Published public private(set) var lastAgentResponse: String = ""
    /// Un-stripped accumulator behind `lastAgentResponse` for the
    /// `agent_chat_response_part` streaming path — see `handle(_:)`.
    private var rawAgentResponseBuffer: String = ""
    /// Set whenever an event arrives whose `type` this class doesn't
    /// explicitly handle, or whenever a websocket-level problem happens
    /// that isn't already surfaced via `connectionState`. A reply that
    /// silently never arrives is otherwise indistinguishable from one this
    /// class just doesn't know how to read — this makes that visible in
    /// `ControlsView` instead of it looking like ElevenLabs "isn't
    /// responding" for no discoverable reason.
    @Published public private(set) var diagnosticNote: String?

    /// Fired (on the main thread) when the `agent_response_complete`
    /// event arrives — the agent has finished generating *and* speaking
    /// its reply. `VoiceConversationController` uses this to know when
    /// it's safe to start listening for the next turn again.
    public var onResponseComplete: (() -> Void)?
    /// Fired the moment the agent starts a turn *without* a preceding
    /// `sendUserMessage` call — i.e. an unprompted opening line some agents
    /// are configured to speak automatically right after connecting.
    /// `VoiceConversationController` uses this to cancel the brief window
    /// it waits before opening the mic for the first time, so it doesn't
    /// start listening — and pick up that greeting through the speaker —
    /// while the agent is mid-sentence.
    public var onAgentTurnStarted: (() -> Void)?

    private let urlSession = URLSession(configuration: .default)
    private var webSocketTask: URLSessionWebSocketTask?
    private var levelDecayTimer: Timer?

    // Playback of the agent's synthesized speech — a nice-to-have on top of
    // the level meter (which is computed from the raw PCM regardless of
    // whether playback itself succeeds).
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var playbackRunning = false
    /// ElevenLabs' WebSocket output format for agent speech — reported back
    /// once in `conversation_initiation_metadata_event
    /// .agent_output_audio_format` (e.g. `"pcm_16000"`, `"pcm_44100"`) and
    /// parsed out in `handle(_:)` below, since agents aren't all configured
    /// for the same rate. 16000 here is just the fallback if that field is
    /// ever missing or unparseable.
    private var sampleRate: Double = 16000

    /// Set true right when a `user_message` is sent, cleared once a reply
    /// is judged finished. Two independent conditions both have to be true
    /// before that happens — see `tryFireResponseComplete()`:
    ///   1. The server thinks it's done generating (either the real
    ///      `agent_response_complete` event, which is opt-in per agent, or
    ///      `resetResponseSilenceTimer`'s fallback if no new chunk arrives
    ///      for a while).
    ///   2. Every audio chunk already received has actually *finished
    ///      playing* (`pendingPlaybackBuffers == 0`).
    /// Firing on (1) alone was the bug behind the mic reopening — and the
    /// agent hearing and replying to the tail of its own still-playing
    /// reply — before playback had actually caught up with what had been
    /// received over the socket.
    private var awaitingResponse = false
    private var serverIndicatedComplete = false
    private var pendingPlaybackBuffers = 0
    private var responseSilenceTimer: Timer?
    /// Extra pause between "every scheduled buffer finished playing" and
    /// actually resuming listening. `pendingPlaybackBuffers == 0` means the
    /// app is done *feeding audio to the speaker*, but the sound itself
    /// takes a beat longer to physically decay in the room — there's no
    /// real echo cancellation here (the mic and the speaker are two
    /// separate `AVAudioEngine`s, which voice-processing/AEC needs to be
    /// the same engine to work), so this settle window is what stands in
    /// for it. Without it, the mic could still occasionally catch the tail
    /// of the reply and send it right back — the "talking to itself" bug.
    private var completionSettleTimer: Timer?
    private let completionSettleDelay: TimeInterval = 0.35
    /// ElevenLabs sends TTS audio in per-sentence bursts, not a steady
    /// stream — a natural pause between sentences can easily run past a
    /// second. 1.5s was tight enough to occasionally mistake one of those
    /// pauses for the reply finishing, which flips `mode` away from
    /// `.speaking` early and cuts the waveform off from ElevenLabs' level
    /// updates entirely until the next chunk arrives and re-syncs it —
    /// reads as the waveform "not responding," not just going quiet.
    private let responseSilenceTimeout: TimeInterval = 3.5

    /// Set by `connect(apiKey:agentID:voiceID:)`, read once by
    /// `openSocket(url:)` when it sends `conversation_initiation_client_data`
    /// — held as a property rather than threaded through as a parameter
    /// since `openSocket` is also the reconnect path called after the
    /// async signed-URL fetch resolves.
    private var pendingVoiceID: String = ""

    public init() {}

    /// `voiceID`, if non-empty, is sent once the socket opens as a
    /// `conversation_config_override.tts.voice_id` (see `openSocket(url:)`)
    /// — lets one preconfigured agent speak in any of
    /// `AgentVoicePalette.voices` instead of just its own dashboard-default
    /// voice. Requires "Enable overrides → Voice ID" to be turned on for
    /// this agent in its ElevenLabs dashboard Security tab; if it's off,
    /// the override is silently ignored server-side and the agent's
    /// default voice speaks regardless of what's passed here.
    public func connect(apiKey: String, agentID: String, voiceID: String = "") {
        let trimmedID = agentID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            connectionState = .error("Agent ID is required.")
            return
        }
        disconnect()
        connectionState = .connecting
        pendingVoiceID = voiceID.trimmingCharacters(in: .whitespacesAndNewlines)

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey.isEmpty {
            // No key: only works for agents explicitly marked public in
            // the ElevenLabs dashboard.
            openSocket(url: publicURL(agentID: trimmedID))
        } else {
            Task { [weak self] in
                guard let self else { return }
                do {
                    let signedURL = try await self.fetchSignedURL(apiKey: trimmedKey, agentID: trimmedID)
                    DispatchQueue.main.async {
                        self.openSocket(url: signedURL)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.connectionState = .error("Couldn't get a signed URL — check the API key and Agent ID. (\(error.localizedDescription))")
                    }
                }
            }
        }
    }

    public func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        levelDecayTimer?.invalidate()
        levelDecayTimer = nil
        responseSilenceTimer?.invalidate()
        responseSilenceTimer = nil
        awaitingResponse = false
        serverIndicatedComplete = false
        pendingPlaybackBuffers = 0
        completionSettleTimer?.invalidate()
        completionSettleTimer = nil
        stopPlayback()
        level = 0
        connectionState = .disconnected
    }

    /// Sends a plain text turn to the agent (the `user_message` event) —
    /// no microphone involved. The agent's spoken reply arrives as a
    /// stream of `audio` events, handled in `handle(_:)` below.
    public func sendUserMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard connectionState == .connected, !trimmed.isEmpty else { return }
        lastUserMessage = trimmed
        awaitingResponse = true
        send(json: ["type": "user_message", "text": trimmed])
    }

    /// Called at the top of every place agent content can start arriving
    /// (`agent_response`, `agent_chat_response_part`, and each audio chunk).
    /// If nothing already flagged that a reply is in flight — i.e. this
    /// wasn't preceded by `sendUserMessage` — this is an agent-initiated
    /// turn (an unprompted greeting), so `onAgentTurnStarted` fires to let
    /// the listener react before more content arrives. A no-op once a turn
    /// is already being tracked, so it's safe to call from every arrival
    /// site without double-firing.
    private func markAgentTurnStartedIfNeeded() {
        guard !awaitingResponse else { return }
        awaitingResponse = true
        serverIndicatedComplete = false
        onAgentTurnStarted?()
    }

    // MARK: - Connection setup

    private func publicURL(agentID: String) -> URL {
        var components = URLComponents(string: "wss://api.elevenlabs.io/v1/convai/conversation")!
        components.queryItems = [URLQueryItem(name: "agent_id", value: agentID)]
        return components.url!
    }

    private func fetchSignedURL(apiKey: String, agentID: String) async throws -> URL {
        var components = URLComponents(string: "https://api.elevenlabs.io/v1/convai/conversation/get-signed-url")!
        components.queryItems = [URLQueryItem(name: "agent_id", value: agentID)]
        var request = URLRequest(url: components.url!)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        struct SignedURLResponse: Decodable { let signed_url: String }
        let decoded = try JSONDecoder().decode(SignedURLResponse.self, from: data)
        guard let url = URL(string: decoded.signed_url) else { throw URLError(.badURL) }
        return url
    }

    /// Always called on the main thread — either directly from `connect()`
    /// (public-agent path) or hopped there explicitly after the signed-URL
    /// fetch resolves (private-agent path) — since it mutates
    /// `webSocketTask`, which `disconnect()` also touches from the UI.
    private func openSocket(url: URL) {
        let task = urlSession.webSocketTask(with: url)
        webSocketTask = task
        task.resume()
        listen()
        // An empty `conversation_config_override` just tells the server
        // "use the agent's own configured defaults" — same as omitting it
        // entirely. Only actually overrides the voice when `pendingVoiceID`
        // is non-empty *and* this agent has "Enable overrides → Voice ID"
        // turned on in its ElevenLabs dashboard; otherwise this field is
        // silently ignored server-side.
        var initiationPayload: [String: Any] = ["type": "conversation_initiation_client_data"]
        if !pendingVoiceID.isEmpty {
            initiationPayload["conversation_config_override"] = [
                "tts": ["voice_id": pendingVoiceID]
            ]
        }
        send(json: initiationPayload)
        startLevelDecay()
    }

    private func listen() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                DispatchQueue.main.async {
                    // A `.goingAway`/cancel from our own `disconnect()`
                    // also lands here — only surface it as a visible error
                    // if we still think we're connected/connecting.
                    if self.connectionState != .disconnected {
                        self.connectionState = .error(error.localizedDescription)
                    }
                }
                return
            case .success(let message):
                switch message {
                case .string(let text):
                    DispatchQueue.main.async { self.handle(text) }
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        DispatchQueue.main.async { self.handle(text) }
                    }
                @unknown default:
                    break
                }
            }
            self.listen()
        }
    }

    private func send(json: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let text = String(data: data, encoding: .utf8) else { return }
        webSocketTask?.send(.string(text)) { _ in }
    }

    // MARK: - Incoming events
    // Reference: https://elevenlabs.io/docs/eleven-agents/api-reference/eleven-agents/websocket
    // Only the events relevant to a level-meter + text-chat preview are
    // handled; tool calls, MCP events, and VAD scores are ignored.

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let type = object["type"] as? String
        switch type {
        case "conversation_initiation_metadata":
            connectionState = .connected
            if let metadata = object["conversation_initiation_metadata_event"] as? [String: Any],
               let format = metadata["agent_output_audio_format"] as? String,
               let parsedRate = Self.sampleRate(fromFormat: format) {
                sampleRate = parsedRate
            }

        case "ping":
            if let pingEvent = object["ping_event"] as? [String: Any],
               let eventID = pingEvent["event_id"] {
                send(json: ["type": "pong", "event_id": eventID])
            }

        case "user_transcript":
            if let event = object["user_transcription_event"] as? [String: Any],
               let transcript = event["user_transcript"] as? String {
                lastUserMessage = transcript
            }

        case "agent_response":
            markAgentTurnStartedIfNeeded()
            if let event = object["agent_response_event"] as? [String: Any],
               let response = event["agent_response"] as? String {
                lastAgentResponse = Self.stripDeliveryTags(response)
            }

        case "agent_chat_response_part":
            // The text-only streaming path (start/delta/stop) some agent
            // configs use instead of — or alongside — `agent_response`.
            // Accumulating the deltas here means a reply still shows up in
            // the Voice section even for an agent that never sends a plain
            // `agent_response` event. Kept as a separate raw buffer so a
            // `[delivery tag]` split across two chunks (see
            // `stripDeliveryTags`) still gets caught — it's re-stripped from
            // the whole accumulated text each time, not chunk-by-chunk.
            markAgentTurnStartedIfNeeded()
            if let part = object["text_response_part"] as? [String: Any] {
                switch part["type"] as? String {
                case "start":
                    rawAgentResponseBuffer = ""
                    lastAgentResponse = ""
                case "delta":
                    rawAgentResponseBuffer += (part["text"] as? String) ?? ""
                    lastAgentResponse = Self.stripDeliveryTags(rawAgentResponseBuffer)
                default:
                    break
                }
            }

        case "audio":
            if let event = object["audio_event"] as? [String: Any],
               let base64 = event["audio_base_64"] as? String,
               let pcmData = Data(base64Encoded: base64) {
                handleAudioChunk(pcmData)
            }

        case "interruption":
            level = 0

        case "agent_response_complete":
            responseSilenceTimer?.invalidate()
            responseSilenceTimer = nil
            serverIndicatedComplete = true
            tryFireResponseComplete()

        case "client_error":
            // Field name inferred from the `_event` suffix convention every
            // other event in this API follows (`ping_event`, `audio_event`,
            // etc.) — ElevenLabs' docs didn't show a literal payload sample
            // for this one at the time this was written. Falls back to a
            // generic message if the shape doesn't match.
            let message = (object["client_error_event"] as? [String: Any])?["message"] as? String
            connectionState = .error(message ?? "The agent reported an error.")

        default:
            // Something arrived that isn't handled above (a tool call, VAD
            // score, or an event this class hasn't been taught about yet).
            // Surfaced rather than silently dropped so "the agent isn't
            // responding" is diagnosable instead of a dead end.
            diagnosticNote = "Received unhandled event: \(type ?? "unknown")"
        }
    }

    /// Parses ElevenLabs' `agent_output_audio_format` strings, e.g.
    /// `"pcm_16000"` or `"pcm_44100"` — the number after the last
    /// underscore is the sample rate in Hz.
    private static func sampleRate(fromFormat format: String) -> Double? {
        guard let underscoreIndex = format.lastIndex(of: "_") else { return nil }
        return Double(format[format.index(after: underscoreIndex)...])
    }

    /// Some agent/voice configs write delivery direction inline in the
    /// reply text — e.g. `"[confidently] Sure, I can help with that."` —
    /// meant for the TTS model, not for display. Strips every `[...]`
    /// segment and collapses whatever double-spacing that leaves behind.
    private static func stripDeliveryTags(_ text: String) -> String {
        var result = text
        while let range = result.range(of: #"\[[^\[\]]*\]"#, options: .regularExpression) {
            result.removeSubrange(range)
        }
        return result
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Audio: level meter + playback

    private func handleAudioChunk(_ pcmData: Data) {
        // Any new chunk means playback isn't actually finished, even if a
        // completion signal already came in and the settle timer below is
        // pending — cancel it and require a fresh one.
        completionSettleTimer?.invalidate()
        completionSettleTimer = nil
        serverIndicatedComplete = false

        // Covers agents that greet with audio only, no accompanying
        // `agent_response`/`agent_chat_response_part` text event.
        markAgentTurnStartedIfNeeded()

        let sampleCount = pcmData.count / 2 // 16-bit samples
        guard sampleCount > 0 else { return }

        var sumSquares: Double = 0
        var floatSamples = [Float](repeating: 0, count: sampleCount)
        pcmData.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let int16Buffer = raw.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                let sample = Double(int16Buffer[i]) / 32768.0
                sumSquares += sample * sample
                floatSamples[i] = Float(sample)
            }
        }
        let rms = (sumSquares / Double(sampleCount)).squareRoot()
        // Same rough headroom boost as AudioLevelMonitor — speech RMS
        // typically peaks well under 1.0.
        level = min(rms * 4, 1.0)

        schedulePlayback(floatSamples)
        resetResponseSilenceTimer()
    }

    /// Fallback for `awaitingResponse`/`onResponseComplete` in case a given
    /// agent doesn't have the `agent_response_complete` client event
    /// enabled (it's opt-in per ElevenLabs' docs) — if no new audio chunk
    /// arrives for `responseSilenceTimeout`, treat the reply as finished so
    /// the conversation loop doesn't get stuck waiting forever after the
    /// first turn.
    private func resetResponseSilenceTimer() {
        guard awaitingResponse else { return }
        responseSilenceTimer?.invalidate()
        let timer = Timer(timeInterval: responseSilenceTimeout, repeats: false) { [weak self] _ in
            guard let self, self.awaitingResponse else { return }
            self.serverIndicatedComplete = true
            self.tryFireResponseComplete()
        }
        RunLoop.main.add(timer, forMode: .common)
        responseSilenceTimer = timer
    }

    /// Only resumes listening once *both* the server thinks the reply is
    /// done *and* every chunk already received has actually finished
    /// playing out loud — see `awaitingResponse`'s doc comment for why both
    /// matter. Reopening the mic while the tail of the reply is still
    /// literally queued in `playerNode` is what let the agent hear (and
    /// reply to) itself. Waits `completionSettleDelay` past that point too
    /// — see that property's doc comment — before actually resuming.
    private func tryFireResponseComplete() {
        guard awaitingResponse, serverIndicatedComplete, pendingPlaybackBuffers == 0 else { return }
        completionSettleTimer?.invalidate()
        let timer = Timer(timeInterval: completionSettleDelay, repeats: false) { [weak self] _ in
            guard let self, self.awaitingResponse, self.serverIndicatedComplete, self.pendingPlaybackBuffers == 0 else { return }
            self.awaitingResponse = false
            self.serverIndicatedComplete = false
            self.onResponseComplete?()
        }
        RunLoop.main.add(timer, forMode: .common)
        completionSettleTimer = timer
    }

    private func startLevelDecay() {
        levelDecayTimer?.invalidate()
        // Agent audio arrives in bursts (each TTS chunk, not a steady
        // stream), so without this the ring's glow would step abruptly
        // between chunks instead of settling smoothly.
        let timer = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            self?.level *= 0.85
        }
        RunLoop.main.add(timer, forMode: .common)
        levelDecayTimer = timer
    }

    private func schedulePlayback(_ samples: [Float]) {
        ensurePlaybackRunning()
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            buffer.floatChannelData?[0].update(from: base, count: samples.count)
        }
        pendingPlaybackBuffers += 1
        // The completion handler fires on an audio-engine thread, not
        // necessarily main — hop back before touching any `@Published`
        // state or calling `tryFireResponseComplete()`.
        playerNode.scheduleBuffer(buffer) { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.pendingPlaybackBuffers = max(0, self.pendingPlaybackBuffers - 1)
                self.tryFireResponseComplete()
            }
        }
    }

    private func ensurePlaybackRunning() {
        guard !playbackRunning else { return }
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
        do {
            try audioEngine.start()
            playerNode.play()
            playbackRunning = true
        } catch {
            // Playback failing doesn't block the level meter above (it's
            // computed from the raw chunk before this is ever called) or
            // the waveform reacting in the pill — but it does mean you
            // won't actually *hear* the reply, which otherwise looks
            // identical to the agent not responding at all.
            diagnosticNote = "Couldn't start audio playback: \(error.localizedDescription)"
        }
    }

    private func stopPlayback() {
        guard playbackRunning else { return }
        playerNode.stop()
        audioEngine.stop()
        audioEngine.disconnectNodeInput(playerNode)
        playbackRunning = false
    }
}
