# RingAnimator

A small design tool for the "AI agent is thinking" ring that lives in your
iOS tab bar. It now ships as two apps sharing one core library, plus code
export for handing the animation off to engineers:

- **RingAnimator** (this package, macOS) — the design tool: live preview,
  every tunable parameter, and an SwiftUI/Jetpack Compose code exporter.
- **RingAnimatoriOS** (sibling Xcode project, iOS) — a real app shell showing
  the ring living in a native iOS tab bar, with all parameters tucked into a
  Liquid Glass settings sheet.
- **RingAnimatorCore** — the shared Swift package library both apps build on:
  models, the ring renderer, the controls form, and the code generators.

## How to run the macOS design tool

You'll need a Mac with Xcode 16 or later installed.

1. Open **Terminal** and go to this folder:
   `cd path/to/RingAnimator`
2. Either:
   - Double-click `Package.swift` — it opens directly in Xcode as a project.
     Select the **RingAnimator** scheme (not the "RingAnimator-Package"
     umbrella scheme) and press Run (▶).
   - Or, to skip Xcode entirely: `swift run RingAnimator` from this folder
     (first build takes a minute).

## How to run the iOS app

The iOS app lives in a separate Xcode project, `RingAnimatoriOS/`, next to
this package (both under the same parent folder). It depends on
`RingAnimatorCore` via a local Swift Package reference.

1. Open `RingAnimatoriOS/RingAnimatoriOS.xcodeproj` in Xcode.
2. Pick an iPhone or iPad simulator as the run destination.
3. Press Run (▶). You'll see a native tab bar (Dashboard / Feed / Devices /
   Routines) with a floating Liquid Glass ring button above it — tap the ring
   to open every parameter in a Liquid Glass sheet.

If Xcode ever shows "Missing package product 'RingAnimatorCore'", it usually
means the local package needs re-resolving: **File ▸ Packages ▸ Resolve
Package Versions**. If that doesn't clear it, fully quit and reopen Xcode
(SwiftPM sometimes holds a stale lock on the package if it's also open as its
own project in another window).

## What's inside the macOS app

The app has two top-level tabs: **Ring Designer** (the original tool) and
**Cue Library** (the LED cue explorer).

### Ring Designer

- **Preview tab** — shows the ring both in a mock tab bar (a native iOS
  26/27-style Liquid Glass tab bar with a separate floating ring pod) and as
  a large standalone preview.
- **Controls sidebar** — switch between the four animation types (Wave,
  Chasing, Alternating, Pulse), adjust speed, line width, diode count, glow,
  and the two gradient colors.
- **Export Code tab** — generates a ready-to-drop-in `ThinkingRingView.swift`
  (SwiftUI) and `ThinkingRingView.kt` (Jetpack Compose) reflecting whatever is
  currently configured. Copy to clipboard or save straight to a file.

### Cue Library

An explorer for every LED cue in the Ziris spec sheet (Onboarding, Mode
States, Emergency, Device Health, and the Smart Home / Health & Wellness /
Voice Assistant future categories) — around 65 cues in all.

- **Sidebar** — every cue grouped by category and subcategory, exactly as
  laid out in the source spec sheet. Search filters by name, subcategory, or
  spec text. A small dot marks any cue that's been tweaked away from its
  default.
- **Detail pane** — a live preview of the cue's current LED pattern, the
  original spec-sheet text for reference, and an editable form (pattern
  style, speed, flash count, hold/fade timing, loop count, primary/secondary
  color, and free-text notes). Edits autosave immediately — there's no
  separate Save step, only **Reset to Default**.
- **Export Library…** — writes the full cue library, with any tweaks
  applied, to a JSON file — handy for handing the finalized behavior spec to
  firmware/engineering.
- **Reset All** — clears every tweak and reverts the whole library back to
  its shipped defaults.

Tweaks persist to `~/Library/Application Support/RingAnimator/cue-overrides.json`
so they survive relaunches. Every cue's shipped default lives in
`LEDCueLibrary.swift` — a handful of rows that had no behavior specified yet
in the source sheet are marked as placeholders in their notes field rather
than invented as if they came from the sheet.

## Animation types

- **Wave** — a smooth gradient sweeps continuously around the ring.
- **Chasing** — a bright comet-like arc chases around the ring's track.
- **Alternating** — string lights: individual diodes (default 30, adjustable)
  spaced evenly around the ring, alternating on and off every other diode.
- **Pulse** — the whole ring breathes, brightness and width pulsing together.

## Notes on the exported code

Both exports use the same math (same phase calculation, same easing per
animation type, same diode layout for Alternating), so the on-device
animation will match what you see in the preview:

- SwiftUI: `TimelineView(.animation)` driving either a
  `Circle().stroke(...)` with an `AngularGradient`, or for Alternating, a
  `GeometryReader` + `ForEach` placing individual diode `Circle()`s.
- Compose: a `Canvas` driven by a `LaunchedEffect` + `withFrameNanos` loop,
  drawing arcs with `Brush.sweepGradient`, or for Alternating, looping
  `drawCircle` calls for each diode.

Feel free to hand these files directly to your iOS/Android engineers — they're
self-contained (no external dependencies) aside from standard SwiftUI/Compose
imports.

## Project structure

```
Nexus Ring App/
  RingAnimator/                        - this SwiftPM package
    Package.swift
    Sources/
      RingAnimatorCore/                - shared library, used by both apps
        Models/
          RingAnimationType.swift      - the 4 animation types
          RingConfig.swift             - all tunable parameters (observable)
        Support/
          Color+Hex.swift              - hex <-> Color conversion
        Views/
          RingView.swift               - the ring itself, all 4 animations
          ControlsView.swift           - the parameters form
        Export/
          CodeGenerators.swift         - SwiftUI + Compose code generation
        CueLibrary/
          LEDCueModels.swift           - LEDPatternStyle, LEDCueParameters, LEDCue
          LEDCueLibrary.swift          - the ~65-cue default dataset
          LEDCueStore.swift            - persistence for tweaked cues
          LEDCuePreviewView.swift      - live renderer for every pattern style
      RingAnimator/                    - macOS app target
        RingAnimatorApp.swift          - app entry point
        Views/
          ContentView.swift            - top-level layout (Ring Designer / Cue Library tabs)
          TabBarPreview.swift          - native Liquid Glass mock tab bar
          ExportView.swift             - code export panel
          CueExplorerView.swift        - cue library sidebar + detail editor
  RingAnimatoriOS/                     - separate Xcode project, iOS app
    RingAnimatoriOS.xcodeproj
    RingAnimatoriOS/
      RingAnimatoriOSApp.swift         - app entry point
      RootView.swift                   - native tab bar + Liquid Glass sheet
```

## Working across two Macs

This project lives in iCloud Drive, so it should stay in sync between your
Macs automatically as long as both have iCloud Drive enabled and the sync has
time to finish. A couple of things worth knowing:

- If you edit and build on both Macs around the same time, iCloud can create
  conflicted copies. For a project like this, it's worth considering a git
  repo (`git init` here, push to GitHub) once you're actively iterating from
  both machines — it gives you real version history and merge safety that
  iCloud file sync doesn't.
- Xcode's derived data / build artifacts don't need to sync — only the
  source files under `Sources/`, `Package.swift`, and the `.xcodeproj` files
  matter.

## Extending it

- Add a new animation: add a case to `RingAnimationType`, a matching branch in
  `RingView.body`'s animation switch, and a matching branch in both
  generators inside `CodeGenerators.swift`.
- Want a third gradient stop, or per-app-state presets (e.g. "listening" vs
  "executing")? The `RingConfig` object is the single source of truth — add a
  property there and thread it through the same three places.
- All types exposed from `RingAnimatorCore` (views, models, `RingConfig`) are
  marked `public`, since both the macOS app and the iOS app consume them
  across a package boundary — `package`-level access won't be visible from a
  separate Xcode project.
