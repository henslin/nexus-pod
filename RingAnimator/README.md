# Nexus Pod

The design tool for the Nexus AI agent's presence: the ring that lives in
the iOS tab bar, the LED cues the physical pod plays, and — in the Lab —
the whole agent: its orbs, controls, containers, flows and the app it
lives in. Three apps share one core library.

- **Nexus Pod** (`RingAnimator/`, macOS) — the design tool. A SwiftPM
  package, not an Xcode project. The ring in an iPhone mockup with every
  parameter, saved animations and use cases, a timeline, the LED cue
  library, exports (SwiftUI, Compose, JavaScript, Blender, GIF, movie), and
  the Lab.
- **RingAnimatoriOS** (`RingAnimatoriOS/`, iOS) — the real app shell: the
  ring in a native Liquid Glass tab bar, every parameter in a settings
  sheet.
- **Nexus Lab** (`NexusLab/`, iOS) — the team viewer: every Lab option full
  screen, swipe between them, a rating and note per option.
- **RingAnimatorCore** (`RingAnimator/Sources/RingAnimatorCore/`) — the
  shared library: models, the ring renderer, the controls, the cue
  library, the Lab, the app's screens, the exporters.

## Privacy

Nothing leaves your Mac or phone unless you switch it on. The app makes no
network connection on its own: no analytics, no crash reporting, no
telemetry, no third-party SDKs (the two vendored kits are local source).
The one outbound connection is the optional ElevenLabs voice agent, which
connects only when you enter your own API key and press Connect; the key
is kept in the Keychain. The microphone is used only when Voice Reactive
or the Lab's Audio Reactive is on, and speech recognition runs on the
device's own model or not at all — if the device can't do it locally, the
transcript stays off and says so. Saved animations, use cases, cues and
Lab state are written to Application Support and UserDefaults on the
device only.

## Requirements

macOS 26 or later with Xcode 26 or later (the app uses Liquid Glass and
SwiftUI shaders); the iOS apps need iOS 26.

## Run

**macOS**
```
cd RingAnimator
swift run RingAnimator          # debug
swift build -c release          # release binary in .build/release
```
Or open `RingAnimator/Package.swift` in Xcode and run the **RingAnimator**
scheme.

**iOS** — open `RingAnimatoriOS/RingAnimatoriOS.xcodeproj` or
`NexusLab/NexusLab.xcodeproj` and run on a simulator or device. If Xcode
reports "Missing package product 'RingAnimatorCore'", close any window
that has the package open on its own and reopen the project; it is a
SwiftPM lock quirk, not a broken project.

## Release

```
cd RingAnimator
./preflight.sh                  # every check; must print "Ready to release"
# bump Packaging/Info.plist
./Packaging/build_and_sign.sh   # release build, Developer ID, notarize, staple, zip
./Packaging/package_patterns.sh # the pattern sources, to ship alongside
```
Output goes to `~/Developer/NexusPod-Release`. Verify what a recipient
gets: `xcrun stapler validate` and `spctl -a -vv` should say Notarized
Developer ID.

## What's inside

**Nexus.** The ring in an iPhone mockup, pinch to zoom, light and dark,
the device finish, the app's screens behind it. Fourteen animation types
(Solid, Wave, Chasing, Alternating, Pulse, Ripple, Wobble, Equalizer, Dual
Chase, Sparkle, Aurora, Liquid Fill, Multi Chase, Bloom), diode mode with
four diode shapes, Liquid Glass settings for the tab bar, voice
reactivity, a pod that can show the ring, a photo or a glyph with a
message above the bar. Animations save by name; use cases group them; a
timeline sequences them.

**Cue Library.** The LED patterns the physical pod plays, imported from
the firmware's own recordings, with a live preview of every style. Edits
autosave to `~/Library/Application Support/RingAnimator/`.

**Lab.** The discovery studio for the agent, led by **Q Branch**: a
specification — a look for every agent state, the menu, the container each
action opens, tap and long press — with one switch. *Autoplay* plays it
end to end on the clock; *Interact* puts the same specification live in
your hand: the real screens, the pod in the tab bar, type an ask or hold
to talk, and the agent answers with quick widgets in its reply and does
the thing to the house. Under it, folded, the parts bin: some fifty orb bases with post effects, the
controls (Ask button, gooey menu, metal, beams), the containers (pod,
capsule, card, sheet, full screen) and the flows. Every option opens on
the defaults set in the pass of 17 September 2026; pin a room to change
its default. Each vendored room states its licence in its rail.

**Export.** SwiftUI and Jetpack Compose sources for the ring, JavaScript,
Blender scripts, GIF and movie renders with real alpha, and the pattern
library as sources. The SwiftUI exports are compiled by `ExportCheck`;
the Compose and JavaScript ones are not yet verified.

## Project structure

```
Nexus Pod/
  CLAUDE.md                  - the long-form notes: how everything works and why
  RingAnimator/              - the macOS app, as a SwiftPM package
    Package.swift
    preflight.sh             - every check before a release
    Packaging/               - Info.plist, build_and_sign.sh, package_patterns.sh
    Sources/
      RingAnimatorCore/      - the shared library
        Models/  Views/  Presets/  CueLibrary/  Export/  Support/
        Lab/                 - the Lab: experiments, Q Branch, quidgets, conversations
        Nexus/               - the app's screens, from the design file
        Shaders/             - Metal shaders (the ring's sweep, the Lab's effects)
        Resources/           - assets: screens, device frames, icons, recordings
      RingAnimator/          - the macOS app target
      *Check/                - the preflight checks (FirmwareFieldCheck, ExportCheck, …)
  RingAnimatoriOS/           - the iOS app, an Xcode project on the same core
  NexusLab/                  - the iOS team viewer, likewise
  Vendor/                    - vendored kits: BorderBeamKit, ThinkingOrbsKit (MIT)
  patterns/                  - the firmware's pattern sources (see CLAUDE.md)
  Docs/                      - briefs and write-ups
```

## Working on it

The repo lives at `~/Developer/Nexus Pod/` with two remotes, `origin`
(GitHub) and `nas`; push to both. `CLAUDE.md` is the real documentation —
how each part works, what was measured, and why decisions went the way they
did. Read it before changing anything that looks odd; most of it is there
because it once looked odd.
