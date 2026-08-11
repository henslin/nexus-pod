import Foundation
import AVFoundation
import Speech

/// One "listen until you pause" utterance capture: mic → live partial
/// transcript → a final transcript once you stop talking (~1.2s of
/// silence) or the recognizer itself reports a final result.
///
/// Turn-taking across multiple utterances (deciding *when* to listen
/// again — e.g. only after an assistant finishes replying) is the
/// caller's job, not this class's — see `VoiceConversationController`.
/// This only ever runs one listen-transcribe-finish cycle per `start()`
/// call, and fully tears itself down (audio tap, engine, recognition
/// task) before calling `onFinalTranscript`, so calling `start()` again
/// immediately afterward from that callback is always safe.
///
/// Needs `NSSpeechRecognitionUsageDescription` (and, same as
/// `AudioLevelMonitor`, `NSMicrophoneUsageDescription`) in the consuming
/// app's Info.plist — without both, macOS/iOS deny the permission prompts
/// outright and this fails silently via `authorizationDenied`.
///
/// `@unchecked Sendable`: `SFSpeechRecognitionTask`'s result callback and
/// `AVAudioEngine`'s tap callback are both `@Sendable` and not guaranteed
/// to run on the main thread. Every mutation of a `@Published` property
/// below is manually routed through `DispatchQueue.main.async`, same
/// pattern as `AudioLevelMonitor`/`ElevenLabsVoiceService`.
public final class SpeechToTextService: ObservableObject, @unchecked Sendable {
    @Published public private(set) var isListening = false
    @Published public private(set) var partialTranscript: String = ""
    /// Live 0...1 mic amplitude, from the same tap used for recognition —
    /// deliberately not a second `AVAudioEngine` input tap (only one tap
    /// is allowed per input node at a time), so this doubles as the level
    /// source for the "listening" waveform instead of a separate
    /// `AudioLevelMonitor` running alongside it.
    @Published public private(set) var level: Double = 0
    @Published public private(set) var authorizationDenied = false
    /// Human-readable reason the last `start()` didn't end up actually
    /// listening — `beginSession()` bails out silently in several places
    /// (no recognizer for this locale, no audio input, engine failed to
    /// start), which from the outside all look identical to "the mic just
    /// isn't picking anything up." Surfaced in `ControlsView` so a failure
    /// like this is visible instead of silent.
    @Published public private(set) var lastError: String?

    /// Fired (always on the main thread) once an utterance is judged
    /// finished. Empty/unrecognized utterances don't fire this.
    public var onFinalTranscript: ((String) -> Void)?

    private let engine = AVAudioEngine()
    // Fixed locale for now — the ElevenLabs agent's own configured
    // language isn't surfaced over the WebSocket in a way this reads, so
    // there's nothing to match it against automatically yet.
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private let silenceTimeout: TimeInterval = 1.2
    private var finished = false

    public init() {}

    public func start() {
        guard !isListening else { return }
        lastError = nil
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                guard status == .authorized else {
                    self.authorizationDenied = true
                    self.lastError = "Speech Recognition permission is \(status == .denied ? "denied" : "not granted") — check System Settings > Privacy & Security > Speech Recognition."
                    return
                }
                self.authorizationDenied = false
                self.beginSession()
            }
        }
    }

    /// Cancels the current utterance without firing `onFinalTranscript` —
    /// used when the conversation loop is turned off mid-listen.
    public func stop() {
        teardown()
        isListening = false
        partialTranscript = ""
        level = 0
    }

    private func beginSession() {
        guard let recognizer else {
            lastError = "No speech recognizer for en-US on this system."
            return
        }
        guard recognizer.isAvailable else {
            lastError = "Speech recognizer is temporarily unavailable — check your internet connection (server-based recognition needs it) and try again."
            return
        }
        finished = false

        #if os(iOS)
        // Same requirement as `AudioLevelMonitor` — iOS won't give
        // `AVAudioEngine`'s input node a real format until the shared
        // session is active in a recording-capable category, or the
        // format guard right below silently bails with no error.
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            lastError = "Couldn't configure the audio session: \(error.localizedDescription)"
            return
        }
        #endif

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        #if !targetEnvironment(simulator)
        // The Simulator reports `supportsOnDeviceRecognition == true` even
        // though it has no actual on-device speech model to run — forcing
        // it there fails immediately with "Failed to initialize
        // recognizer" (a well-known Simulator-only limitation of the
        // Speech framework). Real devices get the (faster, offline-
        // capable) on-device path; the Simulator falls back to Apple's
        // server-based recognition, which works fine but needs internet.
        if recognizer.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true
        }
        #endif
        request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            lastError = "No audio input device found."
            return
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)

            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0 else { return }
            var sum: Float = 0
            for i in 0..<frameCount {
                let sample = channelData[i]
                sum += sample * sample
            }
            let rms = (sum / Float(frameCount)).squareRoot()
            let normalized = min(Double(rms) * 6, 1.0)
            DispatchQueue.main.async { self?.level = normalized }
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            request = nil
            lastError = "Couldn't start the audio engine: \(error.localizedDescription)"
            return
        }

        isListening = true
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            // `SFSpeechRecognitionResult` isn't `Sendable`, so it can't be
            // captured into the `DispatchQueue.main.async` closure below
            // directly (Swift 6 flags that as "risks causing data races") —
            // pull the two plain, `Sendable` values we actually need
            // (`String`/`Bool`) out of it synchronously, right here, and
            // only hand those across.
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let errorDescription = error?.localizedDescription
            DispatchQueue.main.async {
                if let transcript {
                    self.partialTranscript = transcript
                    self.resetSilenceTimer()
                }
                if let errorDescription {
                    self.lastError = "Speech recognition stopped: \(errorDescription)"
                }
                if errorDescription != nil || isFinal {
                    self.finishUtterance()
                }
            }
        }
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        let timer = Timer(timeInterval: silenceTimeout, repeats: false) { [weak self] _ in
            self?.finishUtterance()
        }
        RunLoop.main.add(timer, forMode: .common)
        silenceTimer = timer
    }

    private func finishUtterance() {
        guard !finished else { return }
        finished = true
        let text = partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        teardown()
        isListening = false
        partialTranscript = ""
        level = 0
        if !text.isEmpty {
            onFinalTranscript?(text)
        }
    }

    private func teardown() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
    }
}
