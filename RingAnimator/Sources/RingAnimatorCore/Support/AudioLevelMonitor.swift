import AVFoundation
import Combine

/// Live microphone amplitude, normalized to roughly 0...1, for the "voice
/// reactive" motion effect. Deliberately fails silently — if the mic is
/// unavailable, permission is denied, or `AVAudioEngine` can't start for
/// any reason, `level` just stays 0 rather than crashing or blocking the
/// ring from rendering normally.
///
/// Note: this needs a microphone usage-description string in the
/// consuming app's Info.plist (`NSMicrophoneUsageDescription`) — without
/// it, macOS/iOS will deny the permission prompt outright.
///
/// `@unchecked Sendable`: the `AVCaptureDevice.requestAccess` and
/// `installTap` callbacks are `@Sendable`, so capturing `self` across them
/// requires this type to be provably thread-safe under Swift 6's strict
/// concurrency checking. Every mutation of `level` is manually routed
/// through `DispatchQueue.main.async` below, so this is safe in practice —
/// the compiler just can't verify that on its own for a plain class.
public final class AudioLevelMonitor: ObservableObject, @unchecked Sendable {
    @Published public private(set) var level: Double = 0

    private let engine = AVAudioEngine()
    private var isRunning = false

    public init() {}

    public func start() {
        guard !isRunning else { return }
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            guard granted else { return }
            DispatchQueue.main.async {
                self?.beginTap()
            }
        }
    }

    public func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        level = 0
    }

    private func beginTap() {
        guard !isRunning else { return }
        #if os(iOS)
        // Unlike macOS, iOS won't hand `AVAudioEngine`'s input node a real
        // (non-zero-channel) format until the shared `AVAudioSession` has
        // been put into a recording-capable category and activated —
        // skip this and `outputFormat(forBus:)` below silently reports 0
        // channels, so the guard right after bails out and nothing ever
        // starts, with no error anywhere. This was the actual cause of
        // "voice reactive does nothing" on the iOS app.
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            return
        }
        #endif
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0 else { return }

            var sum: Float = 0
            for i in 0..<frameCount {
                let sample = channelData[i]
                sum += sample * sample
            }
            let rms = (sum / Float(frameCount)).squareRoot()
            // Rough normalization — speech/music typically peaks well under
            // 1.0 RMS, so scale up before clamping.
            let normalized = min(Double(rms) * 6, 1.0)

            DispatchQueue.main.async {
                self?.level = normalized
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
