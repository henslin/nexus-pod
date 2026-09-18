import AVFoundation
import Accelerate
import Combine
import Speech

/// Live microphone input as a level plus three bands — bass, mid,
/// treble — with attack/release smoothing, for the Lab.
///
/// `AudioLevelMonitor` gives one RMS number, which is enough for "the
/// ring swells when you talk". The Lab wants Aurora to churn on bass
/// and Sparks to fire on treble, and a single level can't tell those
/// apart. So: a 1024-point FFT on each tap buffer (`vDSP`), the power
/// summed into three bands, and each band followed by an envelope —
/// fast up, slower down — so a beat reads as a hit and not a flicker.
///
/// Same shape as `AudioLevelMonitor` on purpose (fails silently, main
/// thread writes, `@unchecked Sendable` for the tap closure); see its
/// header for why. The two are not merged because the ring's own path
/// is release code and should not pick up an FFT it doesn't use.
public final class AudioSpectrumMonitor: ObservableObject, @unchecked Sendable {
    /// All 0…1, smoothed.
    @Published public private(set) var level: Double = 0
    @Published public private(set) var bass: Double = 0
    @Published public private(set) var mid: Double = 0
    @Published public private(set) var treble: Double = 0
    /// 1 on the frame a beat is detected, decaying — for one-shot events.
    @Published public private(set) var beat: Double = 0

    /// The live transcript, word by word with when each arrived — for
    /// the Lab's speech-to-text (Chris, 2026-09-15: "a subtle, natively
    /// animated speech to text at the bottom of the screen"). Fed from
    /// the same tap as the FFT: an input node takes one tap, so the
    /// recogniser rides on this one rather than opening its own engine
    /// the way `SpeechToTextService` does.
    @Published public private(set) var words: [LabTranscriptWord] = []
    /// Why the transcript isn't running, when it isn't.
    @Published public private(set) var transcriptError: String?
    /// Turn recognition on or off; takes effect while the tap runs.
    public var transcribing: Bool = false {
        didSet {
            guard transcribing != oldValue else { return }
            if transcribing { if isRunning { beginRecognition() } } else { endRecognition(clear: true) }
        }
    }
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// Words from finished utterances; the live request's words follow.
    private var committed: [LabTranscriptWord] = []
    private var partialCount = 0

    /// Seconds to rise to / fall from a peak. Set from the Lab's knobs.
    public var attack: Double = 0.03
    public var release: Double = 0.25

    private let engine = AVAudioEngine()
    private var isRunning = false
    private let fftSize = 1024
    private var fft: vDSP.FFT<DSPSplitComplex>?
    private var window: [Float] = []
    private var lastBass: Double = 0

    public init() {
        fft = vDSP.FFT(log2n: vDSP_Length(log2(Double(fftSize))), radix: .radix2, ofType: DSPSplitComplex.self)
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: fftSize, isHalfWindow: false)
    }

    public func start() {
        guard !isRunning else { return }
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            guard granted else { return }
            DispatchQueue.main.async { self?.beginTap() }
        }
    }

    public func stop() {
        guard isRunning else { return }
        endRecognition(clear: false)
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        level = 0; bass = 0; mid = 0; treble = 0; beat = 0
    }

    // MARK: Transcript

    private func beginRecognition() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self, self.transcribing, self.isRunning else { return }
                guard status == .authorized else {
                    self.transcriptError = "Speech Recognition is \(status == .denied ? "denied" : "not granted") — System Settings › Privacy & Security › Speech Recognition."
                    return
                }
                self.transcriptError = nil
                self.startRequest()
            }
        }
    }

    /// One recognition request. They end on their own (a pause, or the
    /// recogniser's own limit), so a finished one commits its words and
    /// the next begins — the transcript runs as long as the mic does.
    private func startRequest() {
        guard let recognizer, recognizer.isAvailable else {
            transcriptError = "The speech recogniser isn't available."
            return
        }
        task?.cancel()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        #if !targetEnvironment(simulator)
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        #endif
        request = req
        partialCount = 0
        let requestID = ObjectIdentifier(req)
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            // Neither the result nor the request is Sendable: pull the
            // plain values out here and hand only those to the main thread
            // (see `SpeechToTextService` for the same dance).
            let texts = result?.bestTranscription.segments.map(\.substring)
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            DispatchQueue.main.async {
                guard let self, self.transcribing, let current = self.request, ObjectIdentifier(current) == requestID else { return }
                if let texts {
                    // Keep the arrival time of words already shown; stamp
                    // the new ones now — the animation runs off it.
                    var live = Array(self.words.dropFirst(self.committed.count))
                    if texts.count < live.count { live.removeLast(live.count - texts.count) }
                    for (i, t) in texts.enumerated() {
                        if i < live.count { live[i].text = t } else { live.append(LabTranscriptWord(text: t, at: Date())) }
                    }
                    self.words = self.committed + live
                    if isFinal {
                        self.committed = Array(self.words.suffix(60))
                        self.words = self.committed
                        self.startRequest()
                    }
                } else if failed {
                    // A cancelled or timed-out request: commit and go again.
                    self.committed = Array(self.words.suffix(60))
                    self.startRequest()
                }
            }
        }
    }

    private func endRecognition(clear: Bool) {
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        if clear { words = []; committed = []; transcriptError = nil }
    }

    private func beginTap() {
        guard !isRunning else { return }
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch { return }
        #endif
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }
        let sampleRate = format.sampleRate

        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(fftSize), format: format) { [weak self] buffer, _ in
            guard let self, let data = buffer.floatChannelData?[0] else { return }
            self.request?.append(buffer)
            let n = min(Int(buffer.frameLength), self.fftSize)
            guard n == self.fftSize, let fft = self.fft else { return }

            var samples = [Float](repeating: 0, count: self.fftSize)
            for i in 0..<n { samples[i] = data[i] }
            var rmsValue: Float = 0
            vDSP_rmsqv(samples, 1, &rmsValue, vDSP_Length(n))
            vDSP.multiply(samples, self.window, result: &samples)

            let half = self.fftSize / 2
            var real = [Float](repeating: 0, count: half)
            var imag = [Float](repeating: 0, count: half)
            var magnitudes = [Float](repeating: 0, count: half)
            real.withUnsafeMutableBufferPointer { rp in
                imag.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    samples.withUnsafeBufferPointer { sp in
                        sp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { cp in
                            vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(half))
                        }
                    }
                    fft.forward(input: split, output: &split)
                    vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(half))
                }
            }

            // Bin width = sampleRate / fftSize. Sum power per band, then
            // compress: a log-ish curve so quiet rooms still register and
            // loud ones don't pin every band at 1.
            let binHz = sampleRate / Double(self.fftSize)
            func band(_ lo: Double, _ hi: Double) -> Double {
                let a = max(1, Int(lo / binHz)), b = min(half - 1, Int(hi / binHz))
                guard b > a else { return 0 }
                var sum: Float = 0
                for i in a...b { sum += magnitudes[i] }
                let mean = Double(sum) / Double(b - a + 1)
                return min(1, log10(1 + mean * 40) / 2.2)
            }
            let rawBass = band(30, 250), rawMid = band(250, 2000), rawTreble = band(2000, 9000)
            let rawLevel = min(Double(rmsValue) * 6, 1)

            DispatchQueue.main.async {
                let dt = Double(self.fftSize) / sampleRate
                func follow(_ current: Double, _ target: Double) -> Double {
                    let tau = target > current ? self.attack : self.release
                    let k = 1 - exp(-dt / max(tau, 0.001))
                    return current + (target - current) * k
                }
                self.level = follow(self.level, rawLevel)
                self.bass = follow(self.bass, rawBass)
                self.mid = follow(self.mid, rawMid)
                self.treble = follow(self.treble, rawTreble)
                // Beat: bass jumping well above where it just was.
                let jump = rawBass - self.lastBass
                self.lastBass = self.lastBass + (rawBass - self.lastBass) * 0.3
                self.beat = jump > 0.12 ? 1 : max(0, self.beat - dt / 0.3)
            }
        }

        do {
            try engine.start()
            isRunning = true
            if transcribing { beginRecognition() }
        } catch {
            isRunning = false
        }
    }
}

/// One word of the live transcript and when it arrived.
public struct LabTranscriptWord: Equatable, Sendable {
    public var text: String
    public var at: Date
    public init(text: String, at: Date) { self.text = text; self.at = at }
}
