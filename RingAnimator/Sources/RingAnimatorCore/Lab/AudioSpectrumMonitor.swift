import AVFoundation
import Accelerate
import Combine

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
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        level = 0; bass = 0; mid = 0; treble = 0; beat = 0
    }

    private func beginTap() {
        guard !isRunning else { return }
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch { return }
        #endif
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }
        let sampleRate = format.sampleRate

        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(fftSize), format: format) { [weak self] buffer, _ in
            guard let self, let data = buffer.floatChannelData?[0] else { return }
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
        } catch {
            isRunning = false
        }
    }
}
