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
  Preview tab. Persists to `timeline.json` in Application Support. Not
  yet hosted on iOS, but the model and strip both live in Core for it.

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

Adding a style means four generator backends: SwiftUI, Compose and JS in
`CodeGenerators.swift` (exhaustive switches, so the compiler finds them)
and `BlenderCodeGenerator.swift`, which **dispatches on strings and won't
fail to compile** — it now has an explicit fallback that draws a solid
ring and prints the unhandled style name rather than silently rendering
something else.

Both apps display as **"Nexus Pod"** (rebranded from "RingAnimator"/"Ring
Pod" — display name only, internal identifiers/executable/module names are
still `RingAnimator` throughout, intentionally, see Packaging section).

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

**Signing/distribution (macOS):** `RingAnimator/Packaging/build_and_sign.sh`
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
