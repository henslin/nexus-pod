import Foundation

/// The full default LED cue set, transcribed from the Ziris LED cue
/// specification sheet (Main Category / Cue Name / Ziris behavior columns).
/// These are starting points, not gospel — the whole point of the Cue
/// Explorer is to let the team see what each use case currently communicates
/// and tweak it from here.
///
/// A few source rows didn't have a Ziris behavior specified yet; those are
/// marked in their `notes` field as placeholders rather than silently
/// invented as if they came from the sheet.
public enum LEDCueLibrary {
    public static let all: [LEDCue] =
        onboarding + modeStates + emergency + deviceHealth + smartHome + healthWellness + voiceAssistantFuture

    /// Categories in the same order they appear in the source sheet.
    public static let categories: [String] = [
        "Onboarding", "Mode States", "Emergency", "Device Health",
        "Smart Home (Future)", "Health & Wellness (Future)", "Voice Assistant (Future)"
    ]

    public static func cues(in category: String) -> [LEDCue] {
        all.filter { $0.category == category }
    }

    public static func cue(id: String) -> LEDCue? {
        all.first { $0.id == id }
    }

    /// Cues in a category, grouped into consecutive runs sharing the same
    /// subcategory (preserving sheet order) — handy for building a sidebar
    /// that mirrors the spec sheet's Main Category / Cue Name grouping.
    public static func groupedBySubcategory(in category: String) -> [(subcategory: String?, cues: [LEDCue])] {
        var result: [(subcategory: String?, cues: [LEDCue])] = []
        for c in cues(in: category) {
            if let lastIndex = result.indices.last, result[lastIndex].subcategory == c.subcategory {
                result[lastIndex].cues.append(c)
            } else {
                result.append((c.subcategory, [c]))
            }
        }
        return result
    }

    // MARK: - Onboarding

    private static let onboarding: [LEDCue] = [
        // Power Up
        cue("onboarding.powerUp.plugInPowerUp", "Onboarding", "Power Up", "Plug-in power up",
            "White Solid (10s is the estimated duration for Ziris boot up)",
            solid(white, hold: 10, fade: 0, notes: "10s is the estimated boot-up duration.")),
        cue("onboarding.powerUp.calibrating", "Onboarding", "Power Up", "Ziris calibrating",
            "Off", off()),
        cue("onboarding.powerUp.calibrationComplete", "Onboarding", "Power Up", "Ziris calibration complete",
            "White Solid, Time out after 3s", solid(white, hold: 3, fade: 0)),

        // Bluetooth
        cue("onboarding.bluetooth.pairing", "Onboarding", "Bluetooth", "Bluetooth Pairing",
            "White & Green Ripple", ripple(white, green)),
        cue("onboarding.bluetooth.paired", "Onboarding", "Bluetooth", "Bluetooth Paired",
            "Transition to solid green, Time out after 3s", transitionToSolid(green, hold: 3)),
        cue("onboarding.bluetooth.pairingFailed", "Onboarding", "Bluetooth", "Bluetooth Pairing failed",
            "White & Red Ripple", ripple(white, red)),

        // Wi-Fi
        cue("onboarding.wifi.pairing", "Onboarding", "Wi-Fi", "Wi-Fi Pairing",
            "White & Green Ripple", ripple(white, green)),
        cue("onboarding.wifi.paired", "Onboarding", "Wi-Fi", "Wi-Fi Paired",
            "Transition to solid green, Time out after 3s", transitionToSolid(green, hold: 3)),
        cue("onboarding.wifi.pairingFailed", "Onboarding", "Wi-Fi", "Wi-Fi Pairing failed",
            "White & Red Ripple", ripple(white, red)),
        cue("onboarding.wifi.deviceOffline", "Onboarding", "Wi-Fi", "Device Offline [during onboarding]",
            "White & Red Ripple", ripple(white, red)),

        // Factory Reset — not specified in the source sheet; placeholders only.
        cue("onboarding.factoryReset.initialization", "Onboarding", "Factory Reset", "Factory reset initialization",
            "(behavior not specified in source sheet)",
            ripple(white, amber, notes: "Not specified in source sheet — placeholder default, needs product input.")),
        cue("onboarding.factoryReset.reboot", "Onboarding", "Factory Reset", "Reboot",
            "(behavior not specified in source sheet)",
            off(notes: "Not specified in source sheet — placeholder default, needs product input.")),
        cue("onboarding.factoryReset.complete", "Onboarding", "Factory Reset", "Factory reset complete",
            "(behavior not specified in source sheet)",
            transitionToSolid(green, hold: 3, notes: "Not specified in source sheet — placeholder default, needs product input.")),

        // Firmware Update
        cue("onboarding.firmwareUpdate.updating", "Onboarding", "Firmware Update", "Firmware updating",
            "Blue & Amber Ripple", ripple(blue, amber)),

        // Onboarding complete (sits under the Firmware Update block on the sheet, but is really the finale of onboarding as a whole)
        cue("onboarding.complete.setupComplete", "Onboarding", "Onboarding Complete", "Setup complete",
            "Rainbow transitions to white, fade out after 3s", rainbowFade(hold: 3, fade: 1.0)),

        // Modes Testing in Onboarding
        cue("onboarding.modesTesting.armAway", "Onboarding", "Modes Testing in Onboarding", "Arm Away",
            "Red Spinning → Red Solid → Fade out after 3s", spinThenFade(red)),
        cue("onboarding.modesTesting.armAwayFailed", "Onboarding", "Modes Testing in Onboarding", "Arm Away Failed",
            "No color, only Ear con", earcon()),
        cue("onboarding.modesTesting.armHome", "Onboarding", "Modes Testing in Onboarding", "Arm Home",
            "Amber Spinning → Amber Solid → Fade out after 3s", spinThenFade(amber)),
        cue("onboarding.modesTesting.armHomeSecurityPin", "Onboarding", "Modes Testing in Onboarding", "Security Pin",
            "No Color", noColor()),
        cue("onboarding.modesTesting.armHomeFailed", "Onboarding", "Modes Testing in Onboarding", "Arm Home Failed",
            "No color, only Ear con", earcon()),
        cue("onboarding.modesTesting.standby", "Onboarding", "Modes Testing in Onboarding", "Standby",
            "Green Spinning → Green Solid → Fade out after 3s", spinThenFade(green)),
        cue("onboarding.modesTesting.standbySecurityPin", "Onboarding", "Modes Testing in Onboarding", "Security Pin",
            "No Color", noColor()),
        cue("onboarding.modesTesting.standbyFailed", "Onboarding", "Modes Testing in Onboarding", "Standby Failed",
            "No color, only Ear con", earcon())
    ]

    // MARK: - Mode States

    private static let modeStates: [LEDCue] = [
        // Arm Away
        cue("modeStates.armAway.armAway", "Mode States", "Arm Away", "Arm Away",
            "Red Spinning → Red Solid → Fade out after 3s", spinThenFade(red)),
        cue("modeStates.armAway.armAwayFailed", "Mode States", "Arm Away", "Arm Away Failed",
            "No color, only Ear con", earcon()),

        // Arm Home
        cue("modeStates.armHome.armHome", "Mode States", "Arm Home", "Arm Home",
            "Amber Spinning → Amber Solid → Fade out after 3s", spinThenFade(amber)),
        cue("modeStates.armHome.securityPin", "Mode States", "Arm Home", "Security Pin",
            "No Color", noColor()),
        cue("modeStates.armHome.armHomeFailed", "Mode States", "Arm Home", "Arm Home Failed",
            "No color, only Ear con", earcon()),

        // Standby
        cue("modeStates.standby.standby", "Mode States", "Standby", "Standby",
            "Green Spinning → Green Solid → Fade out after 3s", spinThenFade(green)),
        cue("modeStates.standby.securityPin", "Mode States", "Standby", "Security Pin",
            "No Color", noColor()),
        cue("modeStates.standby.standbyFailed", "Mode States", "Standby", "Standby Failed",
            "No color, only Ear con", earcon()),

        // Delay
        cue("modeStates.delay.exitDelayArmedAway", "Mode States", "Delay", "Exit delay → Armed Away",
            "Red — Accelerating pulse, LED will speed up with countdown, solid after. Solid Red → Fade out after 3s",
            pulseAccelerate(red, hold: 3, fade: 1.0)),
        cue("modeStates.delay.exitDelayArmedHome", "Mode States", "Delay", "Exit delay → Armed Home",
            "Amber — Accelerating pulse, LED will speed up with countdown, solid after. Solid Red→ Fade out after 3s",
            pulseAccelerate(amber, hold: 3, fade: 1.0,
                notes: "Source sheet lists the final hold color as \"Solid Red\" under an Amber heading — likely a typo; using Amber throughout pending confirmation.")),
        cue("modeStates.delay.entryDelay", "Mode States", "Delay", "Entry delay",
            "Amber/Mode color — Accelerating pulse, LED will speed up with countdown, solid after. Solid Red→ Fade out after 3s",
            pulseAccelerate(amber, hold: 3, fade: 1.0,
                notes: "Should track the active arm mode's color (Away = red, Home = amber) — defaulted to amber here.")),
        cue("modeStates.delay.exitDelayCancelled", "Mode States", "Delay", "Exit delay cancelled",
            "No Color", noColor()),
        cue("modeStates.delay.deterrence", "Mode States", "Delay", "Deterence",
            "not applicable", notApplicable())
    ]

    // MARK: - Emergency

    private static let emergency: [LEDCue] = [
        cue("emergency.alarmActive", "Emergency", nil, "Alarm active",
            "Red 3 quick flashes", quickFlash(red, count: 3)),
        cue("emergency.panicGunshotGlassbreakFire", "Emergency", nil,
            "Panic detected/ Gunshot detected/ Glass break detected/ Fire detected",
            "Red 3 quick flashes", quickFlash(red, count: 3)),
        cue("emergency.duressPin", "Emergency", nil, "Duress PIN",
            "No Color", noColor(notes: "Intentionally no visual cue — a duress PIN shouldn't alert anyone nearby.")),
        cue("emergency.police", "Emergency", nil, "Police",
            "Red 3 quick flashes", quickFlash(red, count: 3)),
        cue("emergency.fire", "Emergency", nil, "Fire",
            "Red 3 quick flashes", quickFlash(red, count: 3)),
        cue("emergency.medical", "Emergency", nil, "Medical",
            "Red 3 quick flashes", quickFlash(red, count: 3)),
        cue("emergency.rapidSOS", "Emergency", nil, "Rapid SOS",
            "Red 3 quick flashes", quickFlash(red, count: 3)),
        cue("emergency.alarmCancelled", "Emergency", nil, "Alarm cancelled",
            "Green Spinning → Green Solid → Fade out after 3s", spinThenFade(green)),
        cue("emergency.tamperDetected", "Emergency", nil, "Tamper detected",
            "Amber Flash", flash(amber))
    ]

    // MARK: - Device Health

    private static let deviceHealth: [LEDCue] = [
        cue("deviceHealth.lowBattery", "Device Health", nil, "Low battery (under 10-15%)",
            "Amber Flash", flash(amber)),
        cue("deviceHealth.matterZwaveOffline", "Device Health", nil, "Matter/Zwave devices offline",
            "No Color", noColor()),
        cue("deviceHealth.cameraOffline", "Device Health", nil, "Camera offline (Wi-Fi offline)",
            "not applicable", notApplicable()),
        cue("deviceHealth.manualFirmwareUpdate.inProgress", "Device Health", "Manual Firmware Update", "Firmware update in progress",
            "Blue & Amber Ripple", ripple(blue, amber)),
        cue("deviceHealth.manualFirmwareUpdate.complete", "Device Health", "Manual Firmware Update", "Firmware update complete",
            "Solid Blue", solid(blue, hold: 3, fade: 0.6))
    ]

    // MARK: - Smart Home (Future)

    private static let smartHome: [LEDCue] = [
        cue("smartHome.devicePairing", "Smart Home (Future)", nil, "Smart home device pairing",
            "Arlo voice color (Nexus Color)", voiceAssistant()),
        cue("smartHome.deviceConnected", "Smart Home (Future)", nil, "Smart home device connected",
            "Arlo voice color (Nexus Color)", voiceAssistant()),
        cue("smartHome.devicePairingFailed", "Smart Home (Future)", nil, "Smart home device pairing failed",
            "Arlo voice color (Nexus Color)", voiceAssistant()),
        cue("smartHome.shortcutsAutomations", "Smart Home (Future)", nil, "Shortcut, automations, failure, completions",
            "Arlo voice color (Nexus Color)", voiceAssistant())
    ]

    // MARK: - Health & Wellness (Future)

    private static let healthWellness: [LEDCue] = [
        cue("healthWellness.wellnessCheckDue", "Health & Wellness (Future)", nil, "Wellness check due",
            "Purple", solid(purple)),
        cue("healthWellness.missedWellnessCheck", "Health & Wellness (Future)", nil, "Missed wellness check",
            "Purple", solid(purple)),
        cue("healthWellness.possibleFallDetected", "Health & Wellness (Future)", nil, "Possible fall detected",
            "Purple", solid(purple)),
        cue("healthWellness.fallConfirmedNoResponse", "Health & Wellness (Future)", nil, "Fall confirmed / no response",
            "Purple", solid(purple)),
        cue("healthWellness.medicationReminder", "Health & Wellness (Future)", nil, "Medication reminder",
            "Purple", solid(purple)),
        cue("healthWellness.safeArrivalChildHome", "Health & Wellness (Future)", nil, "Safe arrival / child home",
            "Purple", solid(purple)),
        cue("healthWellness.safeArrivalOverdue", "Health & Wellness (Future)", nil, "Safe arrival overdue",
            "Purple", solid(purple))
    ]

    // MARK: - Voice Assistant (Future)

    private static let voiceAssistantFuture: [LEDCue] = [
        cue("voiceAssistant.listening", "Voice Assistant (Future)", nil, "Voice assistant listening",
            "Arlo voice color (Nexus Color)", voiceAssistant()),
        cue("voiceAssistant.processing", "Voice Assistant (Future)", nil, "Voice assistant processing",
            "Arlo voice color (Nexus Color)", voiceAssistant()),
        cue("voiceAssistant.speaking", "Voice Assistant (Future)", nil, "Voice assistant speaking",
            "Arlo voice color (Nexus Color)", voiceAssistant())
    ]

    // MARK: - Construction helper

    private static func cue(_ id: String, _ category: String, _ subcategory: String?, _ name: String,
                             _ spec: String, _ params: LEDCueParameters) -> LEDCue {
        LEDCue(id: id, category: category, subcategory: subcategory, name: name, specText: spec, defaultParameters: params)
    }

    // MARK: - Color shorthands

    private static let white = LEDCueColors.white
    private static let green = LEDCueColors.green
    private static let red = LEDCueColors.red
    private static let amber = LEDCueColors.amber
    private static let blue = LEDCueColors.blue
    private static let purple = LEDCueColors.purple

    // MARK: - Parameter shorthands
    // Small helpers so the table above reads close to the spec sheet itself.

    private static func solid(_ hex: String, hold: Double = 1.5, fade: Double = 0.6, notes: String = "") -> LEDCueParameters {
        LEDCueParameters(style: .solid, primaryColorHex: hex, secondaryColorHex: hex, holdSeconds: hold, fadeOutSeconds: fade, notes: notes)
    }

    private static func off(notes: String = "") -> LEDCueParameters {
        LEDCueParameters(style: .off, primaryColorHex: LEDCueColors.off, secondaryColorHex: LEDCueColors.off, holdSeconds: 0, fadeOutSeconds: 0, notes: notes)
    }

    /// "No Color" cues are distinct from `.off` in intent: the ring is
    /// deliberately kept dark for privacy/discretion (e.g. entering a PIN),
    /// not because the device has nothing to show.
    private static func noColor(notes: String = "") -> LEDCueParameters {
        LEDCueParameters(style: .off, primaryColorHex: LEDCueColors.off, secondaryColorHex: LEDCueColors.off, holdSeconds: 0, fadeOutSeconds: 0,
                          notes: notes.isEmpty ? "No Color — intentionally no LED cue for this state." : notes)
    }

    private static func ripple(_ primary: String, _ secondary: String, notes: String = "") -> LEDCueParameters {
        LEDCueParameters(style: .ripple, primaryColorHex: primary, secondaryColorHex: secondary, speed: 1.1, holdSeconds: 1.5, fadeOutSeconds: 0, loops: 0, notes: notes)
    }

    private static func transitionToSolid(_ hex: String, hold: Double, notes: String = "") -> LEDCueParameters {
        LEDCueParameters(style: .transitionToSolid, primaryColorHex: hex, secondaryColorHex: hex, speed: 1.0, holdSeconds: hold, fadeOutSeconds: 0, notes: notes)
    }

    private static func spinThenFade(_ hex: String, hold: Double = 3, fade: Double = 1.0, notes: String = "") -> LEDCueParameters {
        LEDCueParameters(style: .spinThenSolidFade, primaryColorHex: hex, secondaryColorHex: hex, speed: 1.3, holdSeconds: hold, fadeOutSeconds: fade, notes: notes)
    }

    private static func pulseAccelerate(_ hex: String, hold: Double = 3, fade: Double = 1.0, notes: String = "") -> LEDCueParameters {
        LEDCueParameters(style: .pulseAccelerateThenSolidFade, primaryColorHex: hex, secondaryColorHex: hex, speed: 0.8, holdSeconds: hold, fadeOutSeconds: fade, notes: notes)
    }

    private static func rainbowFade(hold: Double = 3, fade: Double = 1.0, notes: String = "") -> LEDCueParameters {
        LEDCueParameters(style: .rainbowThenWhiteFade, primaryColorHex: LEDCueColors.white, secondaryColorHex: LEDCueColors.white, speed: 1.2, holdSeconds: hold, fadeOutSeconds: fade, notes: notes)
    }

    private static func quickFlash(_ hex: String, count: Int = 3, notes: String = "") -> LEDCueParameters {
        LEDCueParameters(style: .quickFlash, primaryColorHex: hex, secondaryColorHex: hex, speed: 3.0, flashCount: count, holdSeconds: 0, fadeOutSeconds: 0.3, loops: 1, notes: notes)
    }

    /// A slower, ongoing alert flash that repeats until the underlying
    /// condition clears (low battery, tamper) — `loops: 0` means "forever".
    private static func flash(_ hex: String, notes: String = "") -> LEDCueParameters {
        LEDCueParameters(style: .flash, primaryColorHex: hex, secondaryColorHex: hex, speed: 1.0, flashCount: 0, holdSeconds: 0, fadeOutSeconds: 0, loops: 0,
                          notes: notes.isEmpty ? "Repeats until the underlying condition clears." : notes)
    }

    private static func earcon(notes: String = "") -> LEDCueParameters {
        LEDCueParameters(style: .earConOnly, primaryColorHex: LEDCueColors.off, secondaryColorHex: LEDCueColors.off, holdSeconds: 0, fadeOutSeconds: 0,
                          notes: notes.isEmpty ? "Sound only — no LED change." : notes)
    }

    private static func notApplicable(notes: String = "") -> LEDCueParameters {
        LEDCueParameters(style: .notApplicable, primaryColorHex: LEDCueColors.off, secondaryColorHex: LEDCueColors.off, holdSeconds: 0, fadeOutSeconds: 0,
                          notes: notes.isEmpty ? "Not applicable — no LED behavior defined for this cue." : notes)
    }

    private static func voiceAssistant(notes: String = "") -> LEDCueParameters {
        LEDCueParameters(style: .voiceAssistantColor, primaryColorHex: LEDCueColors.blue, secondaryColorHex: LEDCueColors.purple, speed: 1.0, holdSeconds: 1.5, fadeOutSeconds: 0.6,
                          notes: notes.isEmpty ? "Uses the platform's standard Arlo/Nexus voice-assistant color, not a custom color." : notes)
    }
}
