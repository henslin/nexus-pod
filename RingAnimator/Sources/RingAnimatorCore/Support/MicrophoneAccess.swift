import AVFoundation

/// Why the microphone isn't feeding anything — in plain words, or nil
/// when it is. Both audio monitors used to fail silently: access denied,
/// the session refused, a zero-channel input, the engine not starting —
/// and the ring just didn't react, the meters just sat flat. (Snow
/// Leopard, 2026-09-18.)
public enum MicrophoneAccess {
    /// The system's answer, read fresh: nil when access is granted or not
    /// yet asked for (the first use asks).
    public static var problem: String? {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied:
            #if os(macOS)
            return "Microphone access is off for Nexus Pod — System Settings › Privacy & Security › Microphone."
            #else
            return "Microphone access is off — Settings › Privacy & Security › Microphone."
            #endif
        case .restricted:
            return "Microphone access is restricted on this device."
        default:
            return nil
        }
    }
}
