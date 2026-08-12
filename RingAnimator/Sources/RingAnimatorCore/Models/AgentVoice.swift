import Foundation

/// One selectable voice for the ElevenLabs Conversational AI agent —
/// paired with `AgentVoicePalette`, the `VoiceSection` counterpart to
/// `ApprovedColor`/`ApprovedColorPalette`. `id` is the actual ElevenLabs
/// voice ID (not a locally-invented one), since it's sent verbatim as the
/// `conversation_config_override.tts.voice_id` override on connect — see
/// `ElevenLabsVoiceService.connect(apiKey:agentID:voiceID:)`.
struct AgentVoice: Identifiable, Hashable {
    let name: String
    let id: String
}

/// The fixed roster of voices `config.elevenLabsAgentID`'s agent can speak
/// in. Only takes effect if that agent has "Enable overrides → Voice ID"
/// turned on in its ElevenLabs dashboard Security settings — otherwise the
/// override is silently ignored and it always speaks in its own configured
/// default voice.
enum AgentVoicePalette {
    static let voices: [AgentVoice] = [
        AgentVoice(name: "Liam", id: "FSZ4QLofSALZxepAyq63"),
        AgentVoice(name: "Jarnathan", id: "6HJyroLkuU2Fu1CGBGfJ"),
        AgentVoice(name: "Arlo", id: "7mWSIlIHyeUNofAm3fij"),
        AgentVoice(name: "Jon", id: "enzbGixeo55iqn1QxbbC"),
        AgentVoice(name: "Amy", id: "yNNeOYpectqAXPMUS0vv"),
        AgentVoice(name: "Jessa", id: "yj30vwTGJxSHezdAGsv9"),
    ]
}
