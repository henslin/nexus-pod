# Nexus Pod — Project Context

Claude Code reads this file automatically at the start of every session in
this directory. It exists so a fresh session has the same context this
project built up over a long working session elsewhere — nothing here is
guesswork, all of it reflects the actual current state of the repo.

## What this is

A SwiftUI ring-animation/visualizer app, shipped as two targets sharing one
core library:

- **RingAnimator** (`RingAnimator/`) — the macOS design tool. A SwiftPM
  package, not an Xcode project. Sidebar controls, a phone-mockup preview,
  Liquid Glass tab bar preview, and code export (SwiftUI/Compose).
- **RingAnimatoriOS** (`RingAnimatoriOS/`) — the real iOS app. A separate
  Xcode project (`RingAnimatoriOS.xcodeproj`) that depends on the same core
  via a local Swift Package reference.
- **RingAnimatorCore** (`RingAnimator/Sources/RingAnimatorCore/`) — shared
  library both targets build on: the ring renderer, `RingConfig`,
  `RingPreset`/`RingPresetStore`, use-case models, cue library, demo-app
  screens/assets, exporters. Both platforms stay in sync by depending on
  this one target rather than duplicating code.

### Timeline (sequencing)

`RingTimeline`/`TimelineSegment`/`TimelinePlayer` (Core) compose an
animation out of ordered steps — "fade in, spin three times, go solid,
fade out" — instead of one config looping forever. This is the general
form of what `LEDPatternStyle` already carried as fixed cases
(`.spinThenSolidFade`, `.rainbowThenWhiteFade`, ...); those stay put.

- **A step is a `RingPreset` plus timing.** Reuses the existing snapshot
  type rather than a parallel one, so anything savable to Saved
  Animations can become a step.
- **Editing is Keynote's model**: the timeline is the document and the
  Controls panel is an inspector into the *selected step*. Selecting
  loads that step's snapshot into the live `RingConfig`; every knob turn
  writes back. No commit action. `TimelinePlayer.bind(to:)` sets this up;
  `isApplyingSnapshot` is what stops selection from capturing itself
  back.
- **Length is authored as seconds *or* rotations** (`SegmentLength`), the
  two sides of `rotations = seconds × speed`. Only the authored side is
  stored so they can't drift when speed changes.
- **Phase continuity is the load-bearing math.** `RingView` derives angle
  as `elapsed × speed`, so playing each step from a local zero would
  restart rotation at every boundary and visibly snap.
  `RingTimeline.resolve(at:)` accumulates rotations across steps and
  converts that into each step's own time base (`Resolved.phaseTime`),
  which holds even when adjacent steps spin at different rates — and is
  what makes "spin exactly three times, then go solid" land on a whole
  rotation. Don't "simplify" phaseTime to the raw playhead.
- **Everything is a pure function of time**, matching `RingView`'s
  `overrideElapsed` contract. That's what lets `AnimationExporter` render
  a timeline frame-by-frame with no live clock. Views take playback as a
  `TimelinePlayback` *value* rather than observing the player.
- **Playback renders through `TimelinePlayer.playbackConfig`**, a second
  config, so playing can't write over the step being edited. Steps play
  with `sequencePlaybackEnabled` forced off — the timeline owns fading,
  and leaving the per-step envelope on double-fades.
- **UI**: `TimelineStripView` (Core) under the canvas in the Mac app's
  Preview tab, in `UseCaseDetailView`, and on iOS via `TimelineScreen`
  from the Ring Settings sheet. One view, three hosts.
- **Three separate timelines, three stores.** Nexus's is
  `timeline.json`; each use case gets its own
  `use-case-timeline-<uuid>.json` (see
  `TimelinePlayer.useCaseFileName`), deleted with the use case in
  `UseCaseListView` so it can't be orphaned.

  A file per use case rather than a `timeline` property on `RingPreset`,
  deliberately: `TimelineSegment.snapshot` *is* a `RingPreset`, so giving
  `RingPreset` a timeline would let a step contain a timeline containing
  steps. The type system would allow it and nothing would stop it.

  The Cue Library has no timeline on purpose — a cue is one named
  behavior from the spec sheet, and the multi-phase styles plus
  sequencing in Nexus already cover composition. Adding per-cue
  timelines would create two competing ways to express the same thing.

Not built (deliberately): interpolation between steps, per-property
keyframes, parallel tracks.

### Pattern styles: primitives vs composites

`LEDPatternStyle` now splits two ways, and `isComposite` is the test:

- **Primitives** (`.spin`, `.pulseAccelerate`, `.rainbow`, plus `.solid`,
  `.off`, `.flash`, `.quickFlash`, `.ripple`) do one thing and keep doing
  it. Build new work from these and sequence them on the timeline.
- **Composites** (`.spinThenSolidFade`, `.pulseAccelerateThenSolidFade`,
  `.rainbowThenWhiteFade`, `.transitionToSolid`) are each a primitive
  followed by a solid hold and a fade, welded into one case back when
  there was no way to arrange phases yourself.

**Don't delete the composites.** `LEDCueLibrary` transcribes the Ziris
spec sheet and its rows reference them as ground truth, and saved cue
JSON (`LEDCueStore`) decodes by these exact rawValues. They're grouped
apart in the picker instead, and their renderers *delegate* to the
primitives so the drawing code exists once.

**`.spin` turns at exactly `speed` revolutions/second — that's a
contract.** `SegmentLength.rotations` converts a step's length via
`rotations = seconds × speed`, so a spin at any other rate makes "spin
three times" untrue. The composite `.spinThenSolidFade` scales the
primitive's clock by `3 / 1.1` to reproduce the three turns its
spec-sheet cues were transcribed against — note the factor has no `speed`
in it, since `spinDuration` already carries that dependence.

### Diode mode

`RingConfig.diodeModeEnabled` renders *any* animation as a fixed ring of
diodes that only change brightness and color — how addressable LED
hardware works. Every continuous renderer draws the opposite way (arcs
rotating, gradients sweeping, rings scaling), so none of them is reusable
here; `RingView.diodeIntensity` restates each animation as a scalar field
over ring position instead.

- Alternating, Sparkle, Equalizer and Multi Chase translate **exactly** —
  their mappings are the same expressions their own renderers use, so
  diode mode doesn't change how they look. Keep it that way.
- Ripple and Wobble are **interpretations**, not translations: both are
  radial effects and a fixed pixel ring has no radius to vary, so they
  become a travelling front and a standing wave. That's deliberate.
- `DiodeShape` has two structurally different kinds, which is why
  `dividesTheRing` exists. Round/Square/Bar are *objects positioned on*
  the ring (square and bar rotated tangent to it — axis-aligned ones read
  as scattered dots, not hardware), sized by `diodeScale` and cropped to
  the band. `.segment` *is* the ring, sliced into equal wedges — the
  donut-chart look — so it ignores `diodeScale` and uses `diodeGap`
  instead. `RingView.diodeLayer` is the single place that branches
  between them; all four diode animations go through it.

**Not in the code generators.** They draw each animation the continuous
way, and neither diode mode nor diode shape is reflected there — twelve
animations across four backends is its own piece of work. `ExportView`
says so on screen when either is active rather than silently exporting
something that doesn't match the preview. If you do that work, that
notice is what should come out.

Adding a style means four generator backends: SwiftUI, Compose and JS in
`CodeGenerators.swift` (exhaustive switches, so the compiler finds them)
and `BlenderCodeGenerator.swift`, which **dispatches on strings and won't
fail to compile** — it now has an explicit fallback that draws a solid
ring and prints the unhandled style name rather than silently rendering
something else.

Both apps display as **"Nexus Pod"** (rebranded from "RingAnimator"/"Ring
Pod" — display name only, internal identifiers/executable/module names are
still `RingAnimator` throughout, intentionally, see Packaging section).

## Deployment target — read this before "the UI looks dated"

The package targets **macOS 26 / iOS 26**, set with the *string*
initializer: `platforms: [.macOS("26.0"), .iOS("26.0")]`. The `.v26`
enum case does not exist in this Xcode beta's `PackageDescription`; the
string form does and works.

This is not a formality. The deployment target recorded in the binary is
what makes macOS draw an app with the current control appearance instead
of the legacy one. While this was built at macOS 14, **every system
control rendered in compatibility style** — toggles most visibly — and no
amount of `.glassEffect` or `buttonStyle(.glass)` at the call sites could
change it, because the call sites were never the problem. If the app ever
looks a generation old again, check the binary first:

```
vtool -show-build <path to binary> | grep minos
```

`minos 26.0` is correct. `minos 14.0` means something reset the platform
line in `Package.swift`, and every control in the app will be wrong until
it's put back.

Consequence, stated plainly: the app no longer runs on macOS 14–25. That
was a deliberate trade for the modern appearance. Reverting is a one-line
change to that `platforms:` array plus `LSMinimumSystemVersion` in
`Packaging/Info.plist`.

The `#available(macOS 26.0, *)` checks scattered through the views are
now always true. They're harmless; collapsing them is cleanup, not a fix.

## Build & run

**macOS (RingAnimator):**
```
cd RingAnimator
swift build -c release        # or swift run for debug
```
Xcode can also open `RingAnimator/Package.swift` directly.

**iOS (RingAnimatoriOS):** open `RingAnimatoriOS/RingAnimatoriOS.xcodeproj`
in Xcode and run. If Xcode reports "Missing package product
'RingAnimatorCore'" / "No Destinations": Stop the run, close the
standalone `RingAnimator` package window if it's open (can't have both open
at once), then File > Open Recent to reopen `RingAnimatoriOS.xcodeproj`
fresh. Sometimes also needs Reset Package Caches + Clean Build Folder.
This is a recurring SwiftPM local-package-lock quirk, not a real bug.

**Signing/distribution (macOS):** staging happens in
`~/Developer/NexusPod-Release`, **outside iCloud on purpose** (override
with `NEXUS_STAGE_DIR`). Staging inside the repo fails: `xattr -cr` strips
`com.apple.FinderInfo` before signing, iCloud's file provider puts it back
before `codesign --verify` runs, and the script dies with "resource fork,
Finder information, or similar detritus not allowed". Stripping harder
doesn't win that race.

That bug silently cost a release once — the Aug 26 build was Developer ID
signed but never notarized, because the script died after signing and
nobody checked. Always verify the artifact the way a recipient gets it:

```
xcrun stapler validate "<app>"      # want: The validate action worked!
spctl -a -vv "<app>"                # want: source=Notarized Developer ID
```

`spctl` reporting plain `source=Developer ID` means signed but *not*
notarized — it passes on the machine that built it and warns on everyone
else's.

`RingAnimator/Packaging/build_and_sign.sh`
— builds release, assembles a `.app`, strips iCloud extended attributes
(see Known issues below), codesigns with Developer ID, notarizes, staples,
and zips. One-time setup (signing identity + notarytool credentials) is
documented in the script's own header comments. Run from
`RingAnimator/` with `Packaging/build_and_sign.sh`.

## Packaging naming (important, easy to misread as a bug)

In `build_and_sign.sh`, `EXECUTABLE_NAME="RingAnimator"` and
`BUNDLE_NAME="Nexus Pod"` are deliberately different:
- `EXECUTABLE_NAME` must stay `RingAnimator` — it's the actual compiled
  binary name from `Package.swift`'s `executableTarget`, and matches
  `CFBundleExecutable` in `Packaging/Info.plist`. Renaming the app doesn't
  rename the Swift target.
- `BUNDLE_NAME` is the cosmetic `.app`/`.zip` filename Finder shows —
  currently "Nexus Pod". Change this if you want the shareable file called
  something else; it doesn't touch signing, Info.plist, or the in-app
  display name (that's `CFBundleDisplayName`, set separately in
  `Packaging/Info.plist`, already "Nexus Pod").

## Known issues / recent fixes

- **iCloud + codesign**: this whole repo lives in iCloud Drive, which tags
  synced files with `com.apple.FinderInfo` extended attributes that
  `codesign` rejects ("resource fork, Finder information, or similar
  detritus not allowed"). Fixed by adding `xattr -cr "$APP_BUNDLE"` in
  `build_and_sign.sh` right before signing. If any *other* script ever
  shells out to `codesign` on a bundle in this repo, it'll need the same
  treatment.
- **Stale build artifacts**: `RingAnimator/RingAnimator.zip` and
  `RingAnimator/Packaging/stage/RingAnimator.app` are leftovers from before
  the `BUNDLE_NAME` split above — safe to delete once you've confirmed a
  fresh `Nexus Pod.zip` builds successfully. Not deleted automatically.
- **RootView.swift safe-area bug (fixed)**: iOS background screenshots and
  the floating tab bar were rendering shifted up from the true screen
  edges. Root cause: the top-level `GeometryReader` reported the
  safe-area-inset size by default, but content was later
  `.ignoresSafeArea()`'d *after* being sized/clipped to that smaller box —
  stretching a crop that was never computed against true screen bounds.
  Fix: `.ignoresSafeArea()` moved onto the `GeometryReader` itself so
  `geo.size` is the true full-screen size from the start; explicit
  `geo.safeAreaInsets.bottom` reintroduced only where the tab bar actually
  needs clearance. See the doc comments in `RootView.swift` for the full
  reasoning — deliberately left detailed since this bug is easy to
  reintroduce by "fixing" it the intuitive-but-wrong way.
- **App icon**: current design is an isolated ring only (no glass squircle
  chrome), respecting light/dark mode on macOS, solid black backing on iOS
  (iOS icons must be fully opaque). Source pipeline isn't part of the repo
  build — icons were generated externally and dropped into
  `RingAnimator/Packaging/AppIcon.icns` and
  `RingAnimatoriOS/RingAnimatoriOS/Assets.xcassets/AppIcon.appiconset/`.
  If regenerating, match this look; don't reintroduce squircle/glass
  chrome — that was explicitly removed per product direction ("keep it
  simple with just the ring").
- **Debug `swift build` fails in place; release doesn't.** The debug
  build codesigns `RingAnimator_RingAnimatorCore.bundle` inside
  `.build/`, which is in iCloud, and fails with the same "detritus"
  error as above. Unlike the packaging case, `xattr -cr` does *not* fix
  it — the file provider re-stamps the bundle as fast as it's written.
  Build with a scratch path outside iCloud instead:
  `swift build --scratch-path /tmp/nexus-build`. `swift build -c release`
  works in place, so `build_and_sign.sh` is unaffected (verified).
- **`swift run` shows no window.** A bare SwiftPM binary doesn't reliably
  get a window placed even with the linker-embedded Info.plist and the
  AppDelegate activation fix. To actually *look* at the app, assemble a
  `.app` the way `build_and_sign.sh` does and `open` it — copy the
  release binary + `Packaging/Info.plist` + the `.bundle` from
  `.build/out/Products/Release/` (note `.build/release` is a symlink,
  so `find` skips it without `-L`), `xattr -cr`, then `codesign -s -`.
- **Simulator not usable via Cowork/computer-use**: this was a real
  limitation working on this project outside Claude Code — the iOS
  Simulator wasn't reachable by desktop automation, so UI bugs had to be
  diagnosed from user-provided screenshots instead of live device access.
  Claude Code can build/run/screenshot the Simulator directly via
  `xcodebuild`/`xcrun simctl` — use that instead of asking for manual
  screenshots when debugging UI issues here.

## Earmarked: "Snow Leopard" pass

Named for the release that shipped no new features and just made the
existing ones right. These are all known, deliberate gaps rather than
bugs — the reason each was deferred is recorded where the code lives, and
none of them should be picked up piecemeal while feature work continues.

- **Code generator parity.** The four export backends (SwiftUI, Compose,
  JS, Blender) don't reflect Diode Mode or `DiodeShape` at all, and
  export Multi Chase as two colors where the app does N. `ExportView`
  states these on screen so nobody is surprised — clearing the gap means
  clearing those notices too. `RingView.diodeIntensity` is the shape the
  generators would follow: each animation as a scalar field over ring
  position.
- **Kotlin and JavaScript exports are unverified.** `swift run
  ExportCheck` typechecks all 30 SwiftUI exports (see below) and found
  four that didn't compile. The Compose and web generators emit the same
  shapes from the same templates and have never been compiled at all —
  assume the same class of bug is sitting in them. Needs `kotlinc` and
  `node`, neither of which was available when the check was written.
- **iOS hosting.** `TimelineStripView` and the whole timeline model live
  in `RingAnimatorCore` specifically so iOS can host them, but
  `RingAnimatoriOS` doesn't yet. Real work, not duplicated work.
- **Timeline depth.** Interpolation between steps, per-property
  keyframes, and parallel tracks were all deliberately left out of the
  first cut. Interpolation is the one that changes the data model.
- **Blender's string dispatch.** Both chains (style and animation) now
  have explicit fallbacks that print the unhandled name, after two
  separate incidents of new cases silently rendering as something else.
  Worth converting to something the compiler can check.
- **Nine concurrency warnings, deliberately left.** Five in
  `ZoomableCanvas` (a KVO observer on `magnification` touching
  main-actor state from a closure the compiler treats as `@Sendable`) and
  four in `AnimationExporter` (AVAssetWriter/Input/Adaptor captured in a
  `@Sendable` continuation). Both are correct at runtime — AppKit fires
  that KVO on the main thread, and the writer callbacks are serialized on
  their own queue — the compiler just can't prove it.
  `MainActor.assumeIsolated` is the likely fix for the first. They were
  left alone because silencing them means restructuring a hard-won
  pinch-to-zoom path (see `ZoomableCanvas`'s own comments) and a working
  movie exporter, and a wrong "fix" there is a runtime bug traded for a
  clean build log. Verify movie export end to end and the zoom gesture by
  hand before touching either.

## Hardware-fidelity parameters

A hand-written Blender ring script (`ripple.py`) turned out to be a
better spec for this app than anything written for it, because it had to
survive contact with a real driver. These came from it:

- **Ripple drops.** `.ripple` in Diode Mode is N drops landing at seeded
  positions and expanding symmetrically, not one front from a fixed
  point. Overlapping fronts **add** and are then normalized against the
  loop's peak — take the max instead and crossing ripples read as two
  shapes passing through each other rather than water.
- **`loopSeconds` is load-bearing, not decoration.** Each drop is
  evaluated one loop earlier and later, so a drop landing near the end
  carries into the next pass. Remove that and the seam becomes visible as
  a stutter.
- **`diodeFloor`** lifts *and compresses* — `floor + (1 - floor) * level`,
  not `max(floor, level)`. A plain max clips the low end flat.
- **`firmwareTickMs`** snaps rendered time to a driver's update rate.
  Rendering at 60fps flatters designs that stutter on device; this is the
  preview telling the truth.
- **`DiodeColorMode.byLevel`** takes color from brightness rather than
  index, because ring drivers hold a couple of color registers and a
  global fade — "white at the hot core" is a strength effect, not a third
  color.

`rippleNormalization()` is a per-frame sweep. It must stay hoisted in
`diodeFieldRing` — calling it from inside `diodeIntensity` makes it run
per diode per frame, which is where it started and why it's commented.

## Three Blender importers, doing different jobs

- `CodeGenerators.applyBlenderCode` reads **this app's own export** by its
  `NEXUS_PARAMS` block. Exact round-trip; fails cleanly on anything else.
- `BlenderScriptImporter` reads **someone else's scene script** — a
  hand-written ring animation against their own scene, with no agreed
  format. It scrapes module-level uppercase `NAME = value` constants
  (numbers and 3-tuples) and maps the ones it recognizes: LED count,
  floor, speed, front width, drop count, palette, and the style named in
  the header.
- `FirmwarePatternImporter` reads a **firmware pattern module** out of the
  `patterns/` library — the files that drive the physical ring.

Both UI entry points call `BlenderScriptImporter.apply`, which tries the
exact reader first and routes firmware modules to the third. Adding the
routing there rather than at the buttons is what keeps Nexus and Use Cases
from drifting apart.

### Why the third one exists

A firmware pattern module is built inside-out relative to a scene script:
it imports its constants and its maths from a shared `pattern_common`,
keeps almost nothing at module level, and puts every tunable *inside*
`schedule_*` as an ordinary lowercase local. The uppercase scraper finds
nothing in one, so all 69 files reported "nothing to import" — which reads
as a broken importer rather than a mismatched one.

What those files do expose reliably is the **shared helper they delegate
to** (`_schedule_wake_bloom`, `_schedule_braided_twist`, ...), their
palette as inline `(r, g, b)` tuples or named constants, and their timing.
Resolution runs strongest-first: named helper, then the module's own name,
then `DESCRIPTION` prose, then a rendering primitive. That order is
load-bearing twice over:

- **Name before prose.** `spinning_rainbow_quad` describes itself in a way
  that mentions ripples; read prose-first it imported as a Ripple.
- **`_schedule_level_threshold` is a primitive, not a behavior.** It maps
  a per-LED level onto the two palette registers. Seventeen files call it,
  and they are a shimmer, a strobing lattice and a swinging hotspot — not
  seventeen liquid fills. Same for `_in_any_arc`, which is a geometry test
  that co-occurs with the real signal.

Locals are whitelisted by name, never scraped wholesale: these bodies also
contain `t_ms = 0` and `last_c0 = ...`, which look identical to tunables
to a line-based reader.

`pattern_common.py` and `led_ring_patterns.py` **are** in the folder, so
the helpers' real defaults are read rather than guessed: 2200 ms per lap
and a 5-LED trail for `_schedule_spin_solid_fade`, 312 ms per frame for
`_schedule_spin_firmware`, the firmware `RGB_*` palette (green is pure
`(0, 255, 0)`, amber `(255, 126, 0)`), and `FADE_TAU_MS` for what a fade
rate index actually means in milliseconds. The 16-LED ring size comes from
`pattern_common`'s geometry — `TOP_LEDS = [0, 15]`, opposite is `(i + 8)`,
8 symmetric pairs — since `TOTAL_LEDS` itself lives in the still-absent
`led_ring_core`.

Two things that reading the library corrected:

- **`_schedule_spin_firmware` is not a spin.** Each frame lights *two*
  LEDs, cw `k` and ccw `15-k` — a mirrored pair sweeping in opposite
  directions, which is Dual Chase here.
- **`_schedule_level_threshold` hard-quantizes.** It emits `0x07` or
  `0x00` per LED against a threshold, so these are two-color patterns with
  crisp edges, not smooth gradients.

The per-LED maths still isn't reproduced — helper names map to this app's
nearest behavior, so expect a close match in color and cadence rather than
a frame-exact one. The report says so.

**The library is not a pattern.** `pattern_common.py` sits in the same
folder and passes every structural test a pattern module does; read as one
it imports as whichever helper it defines first. The discriminator is
definition versus use: the library *defines* `_schedule_*`, a pattern only
calls them.

### Sixty-six patterns replay the device's own command stream

`FirmwarePatternStream` ships each pattern's literal command stream and
replays it. Every scheduler is run once, offline, against a recorder that
captures each `set_color0` / `set_color1` / `select_led` / `select_all_leds`
call with its timestamp — the exact bytes the device receives. Replaying
that is not a reproduction of the animation; it *is* the animation.

This exists because the level-threshold engine below covers 21 patterns and
the other 45 schedule LED commands directly: comets stepping head and tail,
cascades filling frame by frame, Perlin fields sampled per tick, palette
rewrites mid-animation. There is no closed form to port, and transcribing 45
hand-written bodies would only ever *approach* what the recording already is.

**Frame semantics.** Two palette registers, and per LED a selection bit plus
a register choice: not selected → dark; selected with bits `0x00` → Color0;
`0x07` → Color1. "Off" is usually Color0 being black rather than a deselect,
so both paths have to be honored — treating `0x00` as off blanks half the
library.

**Resolve the frame once per frame, never per diode.** Replay is a walk over
the event list; doing it sixteen times per frame is sixteen times the work
for one answer. `RingView` resolves it before the diode loop, next to
`rippleNormalization()`, which is there for the same reason.

Regenerate with `Sources/FirmwareFieldCheck/record_streams.py` when the
pattern library changes. `firmware-streams.json` (180 KB) is a committed
resource, so neither the app nor its checks need a copy of the library.

### The fidelity ladder

An imported pattern can hold three levels at once, and they nest — clearing
one reveals the next rather than dropping to nothing:

1. **Recorded stream** — the device's literal output.
2. **Exact field** — the firmware's own `level(i, t)` maths, ported and
   verified sample for sample. Parametric, so speed and palette still mean
   something.
3. **Interpreted** — this app's nearest equivalent animation, fully editable.

`FirmwareFidelitySection` shows which level is active and steps down one at
a time. It sits directly above Animation because levels 1 and 2 override
`animationType`, and an override should be read before the control it
overrides. It's hidden entirely when no firmware pattern is loaded — a card
reading "Interpreted" on every hand-authored design is noise.

**Coverage: 66 of 69 exact.** The three that aren't are the ripple family
(`ripple_green`, `ripple_blue_white`, `listening`), and only because
`pattern_common._import_ripple_math()` needs a `ripple.py` that isn't in the
folder. Drop one in and re-run the recorder and they join the rest.

### Twenty-one patterns also have their maths ported

`FirmwareLevelField` ports the firmware's own per-LED `level(i, t_s)`
functions to Swift. Twenty-one of the patterns are built on one shared
engine, `_schedule_level_threshold`, which takes such a closure, samples it
every 100 ms for every LED, and writes one of two palette registers
depending on whether the sample cleared a threshold. That is the entire
rendering model, and `RingView` already evaluates animations as a scalar
field over (diode, time) — the same shape — so `diodeIntensity`
short-circuits to the field when `RingConfig.firmwareLevelField` is set.

**Two colors, both lit.** The engine opens with `select_all_leds(True, 0x00)`
and never deselects, so every diode is always full brightness and the level
picks its *color*, not its intensity. There is no ramp between the two
states; the quantization is what gives these patterns their crisp edges, and
smoothing it would be a prettier animation than the device can produce.

**The port is bit-identical, and that is checked.**
`swift run FirmwareFieldCheck` checks both halves — 13440 field samples
and 94256 LED-frames of recorded stream. It compares every field against
ground truth
captured from the real Python — `_schedule_level_threshold` is stubbed to
grab each closure, which is then sampled over a 16 x 40 grid and written to
`firmware-levels.json` at full precision. 13440 samples, worst delta 0.0.
Run it before a release, alongside `ExportCheck`.

The check is deliberately exact rather than tolerant: these feed a hard
threshold, so a last-bit difference flips a diode between palette registers
and the pattern visibly changes. Two things had to be right for that:

- **`roundHalfToEven` is Python's `round`.** Swift's `rounded()` is
  half-away-from-zero and they disagree at exactly the half-integers
  `strobe_pulsing_lattice_red` hits — `i / step` lands on 0.5 and 2.5 for a
  16-LED ring with 4 anchors.
- **`pmod` is Python's `%`,** which takes the sign of the divisor.

Parameters are the values the closures actually capture, read out of
`__closure__` rather than transcribed by eye — which is also where the real
thresholds came from. Three patterns override the 0.5 default (0.42, 0.55,
0.35) and look wrong without it, and several declare no `DURATION_MS` at
all, so the field is the only place their true loop length appears.

### Multi-phase patterns import as timeline steps

Several of these engines are sequences, not loops, and flattening one into
a single config keeps only whichever phase won. `Outcome.timeline` carries
the phases when there are any, and both import buttons install it via
`TimelinePlayer.installImported`, which also selects step one so the
Controls panel shows the imported pattern.

Four families sequence, covering 13 files:

| engine | steps |
| --- | --- |
| `_schedule_spin_solid_fade` | spin x2 (4.8 s), solid (3.1 s), fade out (1.5 s) |
| `_schedule_connected_flow` | breathe 3 x 4 s, bloom (4 s), solid (1.4 s) |
| `_schedule_solid_firmware` | solid (`hold_ms`), off (`off_ms`) |
| `_schedule_battery_cascade` | fill (`num_leds` x 500 ms), 8 blink cycles (4.8 s) |

The hand-written patterns that sequence get one too, keyed on the module
name since they have no helper call — `alarm_sos` (500 ms lead-in, 4 x
{3 flashes at 110/170 + 800 ms gap}, 500 ms trail), `battery_100`,
`booting_up`, `device_offline`, `spotlight_deterrence` (the seven phases
its docstring names, 14 steps at 21.68 s), and the two `firmware_update`
cycles that alternate blue/amber each loop. Their numbers and their colors
are transcribed from the body rather than inferred: a phase means
`deterrence_rgb = (180, 35, 0)`, not whichever palette entry sorted first.

A burst of N flashes is one step using the Flash style with a matching
`flashCount`, not N on/off pairs — the primitive already renders exactly
that, and three steps per burst would make a four-cycle alarm a twenty-step
document.

Everything else loops one behavior and is fully described by its config; a
one-step timeline would just be a document to manage.

**`booting_up` is the one deliberate mismatch.** Its phases come to a 6 s
loop against a declared 30000 ms, because the header counts the renderer
repeating that loop five times. The timeline models the loop.

### Follow a hand-off to the sibling module

`wifi_critical.py` is one line — `return schedule_bluetooth_critical(...)` —
and `wifi_failed.py` the same. Read alone they have no behavior to find and
fall back to a keyword in their one-line description.
`readScriptFollowingDelegation` resolves the named module against the
folder the user opened and imports that instead, reporting the hand-off so
the file you picked isn't silently swapped for another.

One hop only, and `schedule_steps` is excluded — that's the step player in
`led_ring_core`, not a pattern. A file that also has its own
`add_event_at_time_ms` body is doing its own work and merely calls a
sibling at the end, so it isn't treated as a hand-off.

**The phase durations are a check, not an estimate.** Each family's steps
sum to the `DURATION_MS` its own callers declare, and that is how two real
errors surfaced:

- **The 50 ms tick quantizes lap times.** `_schedule_spin_solid_fade`
  computes `step_ms = round(2200/16/50)*50`, so 137.5 ms becomes 150 ms and
  a lap really takes 2400 ms, not the requested 2200. `_dual_comet_varied`
  does the same, turning 3000/3400 ms laps into 2400/3200. Using the
  requested figures left every one of these patterns short.
- **There's a 100 ms settle gap** between the comet's last frame and the
  solid snap (`solid_at = spin_end + 100`). It sits on the solid step so
  the spin can stay `.rotations(2)` — the lap count is what's worth
  preserving if anyone retunes the speed.

If you add a family here, check the sum against `DURATION_MS`. It caught
both of the above.

### Import resets first

`BlenderScriptImporter.apply` interprets into a fresh `RingConfig` and
commits it with `RingPreset` only if something was understood. Both
readers set only the knobs they recognize, so importing over a tuned
config used to leave the rest of that tuning in place — a pattern that
says nothing about glow or particles inherited whatever the last one used,
and the ring was a blend of two files. Committing only on success is the
other half: a file that maps to nothing leaves the existing design
completely untouched, which is what "Nothing to import" should mean.

`RingPreset` is the copy mechanism because it already knows which fields
are part of an animation — preview sizing, background staging and voice
credentials deliberately aren't, so an import doesn't clear the backdrop
along with the animation. The exact `NEXUS_PARAMS` round-trip does *not*
reset, since it writes every field it knows about by definition.

### Normalize line endings before parsing

`BlenderScriptImporter.apply` strips `\r` before either reader runs. Both
are line-based and both parse the tail of a line as a value, so a trailing
carriage return makes `Double("14.0\r")` nil and stops
`"(30, 220, 110)\r"` from ending in a paren — every knob silently reads as
absent. Every file in `patterns/` is CRLF while the LF scene script this
was originally built against isn't, so the whole class of bug hid behind
the test case. Don't add a parser that splits on `\n` upstream of that
normalization.

`BlenderScriptImporter` is deliberately an **interpretation**, and it
reports itself as one — the `Outcome` carries what it applied *and* what
it understood but had nowhere to put, and `BlenderImportReportView` shows
both every time. The failure that matters here isn't rejecting a file;
it's silently importing half of one and leaving someone to wonder why the
ring doesn't match their render. If you extend the mapping, extend the
dropped list too.

Unit conversions are the fiddly part: these scripts express speed in ring
positions per second and widths in LED units, both of which need the LED
count to become the app's laps-per-second and ring fractions. Without a
recognized LED count those get dropped rather than misread — a raw 5.5
into `speed` would be wildly wrong.

## Verifying the code generators

The generators emit **strings**. The package builds no matter what those
strings say, so a generated file that doesn't compile is invisible until
someone pastes it into Xcode. Four such bugs shipped before anyone
checked.

```
swift run ExportCheck
```

Generates every SwiftUI export (13 animation types × particles on, plus
all 17 cue styles) and runs `swiftc -typecheck` over each. Exits non-zero
on failure. Run it before a release, and after touching any generator.

All four bugs it caught were the same trap, worth knowing before writing
generator code: **a `@ViewBuilder` closure accepts `let` bindings and
view expressions only.** `var`, `for`, and deferred-initialization
`let x: T` + `if/else` all make the builder try to conform `()` to
`View`. Use ternaries, or move the logic into a helper function the
template emits — `brightestComet` in the SwiftUI template is there for
exactly that reason.

## Open items (not yet done)

- **TestFlight app name**: TestFlight was still showing an old app name to
  testers. This is a separate App Store Connect metadata field ("App
  Information → Name" at appstoreconnect.apple.com), independent of the
  binary's `CFBundleDisplayName` — not fixable from Xcode or this repo.
  Needs a manual edit in the App Store Connect web portal. Unconfirmed
  whether this has been done yet.
- **Local test data**: `~/Library/Application Support/RingAnimator/` may
  still hold local `saved-presets.json`/`use-cases.json` test data on the
  dev machine. This is *not* shipped (confirmed — `RingPresetStore` has no
  seed data, `SavedPresetsView`/`UseCaseListView` already have correct
  empty states + Add buttons), it's purely local dev-machine state. Never
  explicitly asked to be cleared.

## Git

Local repo only — **no remote configured**. Safe to rewrite local history
(amend, rebase) if needed. Latest commits, most recent first:
```
9fd225d Fix RootView background/tab bar safe-area layout bug
48d88ef Simplify app icon to isolated ring, no glass squircle background
a055099 Update app icon with new source art (Mac + iOS)
3578602 Rename app display name to Nexus Pod (Mac + iOS)
ab9b24a Add new Liquid Glass app icon (iOS icon set + macOS .icns)
```
`.gitignore` note: patterns with a slash are root-anchored in git, so
nested build output needs `**/` prefixes (e.g. `**/Packaging/stage/`) —
already fixed once after this bit a commit; keep it in mind adding new
ignore rules.

## Preferences worth knowing

- Direct, concise answers — no padding, no re-explaining what was just
  done.
- Push back on bad ideas rather than just agreeing.
- Verify claims against the actual running app/build output before
  reporting something fixed or done.
