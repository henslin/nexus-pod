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

**Signing/distribution (macOS):** both the *build* and the *staging* happen
outside iCloud on purpose — `~/Developer/NexusPod-Build` (override with
`NEXUS_BUILD_DIR`) and `~/Developer/NexusPod-Release` (`NEXUS_STAGE_DIR`).

Neither can live in the repo. `xattr -cr` strips `com.apple.FinderInfo`
before signing, iCloud's file provider puts it back before
`codesign --verify` runs, and the step dies with "resource fork, Finder
information, or similar detritus not allowed". Stripping harder doesn't win
that race. The build needs the same treatment as the staging, because
SwiftPM codesigns the resource bundle *during* the build — an in-tree
`swift build -c release` fails before any of the signing steps run.

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

### Cutting a release

Both scripts locate themselves, so run them by full path from anywhere:

```
cd "/Users/chris/Library/Mobile Documents/com~apple~CloudDocs/Claude/Nexus Ring App/RingAnimator"
./preflight.sh                      # four checks, ~1 min
# bump Packaging/Info.plist — the script doesn't
./Packaging/build_and_sign.sh       # signs, notarizes, staples, zips
./Packaging/package_patterns.sh     # the pattern sources, to ship alongside
```

**Quote the path, and `cd` into `RingAnimator` first.** The repo root has no
`Packaging/`, so `Packaging/build_and_sign.sh` from one level up fails with
`No such file or directory` — which reads like a missing script rather than a
wrong directory. An unquoted path gives the same message, because it splits
at the space in "Mobile Documents".

`preflight.sh` runs the firmware-fidelity check, the export typecheck, the
pattern-library manifest and an iOS build, each with the scratch path it
needs, and prints one ready/not-ready verdict. It's a script rather than a
list here because the list was wrong the moment it was written — every one
of those commands fails in-tree without `--scratch-path`, and a checklist
you have to remember to decorate is one that gets run wrong.

The manifest check is the one people will skip. It is the only thing that
catches a pattern edited upstream and synced down, which leaves the
committed recordings silently describing an animation the device no longer
plays.

`package_patterns.sh` zips the pattern sources with a README and the
manifest, and refuses to build if the library doesn't match the app's
committed recordings — shipping sources that disagree with the embedded
streams would look like proof while being wrong.

To rehearse the packaging without submitting anything to Apple, run
`build_and_sign.sh` with everything from `→ Submitting to Apple notary
service` onward removed. It will build, assemble, sign and verify — which is
where the failures actually happen. Verified working at 2.1: `valid on
disk`, `satisfies its Designated Requirement`, `source=Developer ID`.

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

## Sections you make yourself

The sidebar's `+` creates a `UserSection`: a named list of animations with
its own `RingPresetStore` file and, per animation, its own timeline. It is
shaped **like Use Cases and not like the other two**, because Use Cases is
the only one of the three it makes sense to have more of — Nexus is a
single live ring, so a second one would be a second app, and the Cue
Library is a transcription of the hardware spec, which a user-created copy
of would stop being.

The button is just `+`, deliberately. Any label would have to name what it
makes, and these aren't folders: they don't contain the built-in sections,
and each is its own list with its own storage.

Three things that would otherwise bite:

- **`AppSection` is no longer a plain `String` enum.** It has a `.user(UUID)`
  case, so it isn't `CaseIterable` any more — `AppSection.fixed` is the
  built-in three. A user section's *name* deliberately isn't in the case:
  it can be renamed, and a copy in the selection would be a second one to
  keep in step.
- **One store per section, cached.** `SectionStores` hands out a
  `RingPresetStore` per id and keeps it. Building one per redraw would drop
  the list's `@Published` identity and re-read the file every time.
- **Deleting a section deletes its files.** Its presets JSON *and* every
  per-preset timeline in it, which are keyed by preset ids that exist
  nowhere else once the section is gone.

**Reordering** is `.onMove` on the store's array, which is already the
list's order: user sections in the sidebar, and animations inside Use
Cases, Nexus's Saved Animations, and any user section. Timeline steps
already reordered by drag (`TimelinePlayer.moveSegment`), so that one
needed nothing.

The Cue Library deliberately has no `+`. It's a fixed transcription of the
hardware spec with per-cue overrides, and staying trustworthy as a spec is
what it's for.

## Exporting a whole list at once

`BatchExportView` renders every animation in a list to GIF and/or movie
into one folder — **Share → Render → Export All as GIF or Movie…** in
Nexus's Saved Animations, Use Cases, and any user section. The single-file
sheet exports whatever the ring is showing, which with a pattern library
imported is sixty-nine trips through a save panel.

Four things it has to do, each for a reason:

- **One at a time.** `ImageRenderer` drives AppKit, so rendering is
  main-actor bound and can't be parallelised. Sixty-nine animations is a
  long wait, which is why the progress line names the animation being
  rendered and the bar counts partial progress within it — a bar that moved
  once per item would sit still on the slow ones and read as hung.
- **A fresh `RingConfig` per preset.** These carry recorded streams and
  firmware fields; reusing one config would leave a previous animation's
  settings in place and export the wrong thing for anything that doesn't
  set every field.
- **Delete an existing `.mov` first.** `AVAssetWriter` refuses to start
  when something is already at the destination, which on a second run into
  the same folder is every file. The GIF writer overwrites happily, so this
  looks asymmetric and isn't.
- **Collect failures, don't abort.** One animation that renders nothing
  shouldn't abandon the other sixty-eight; the summary names what failed.

## Preview and Code, in every section

`DetailPane` is the Preview/Code control plus the two panes under it, and
all three sections use it. The control used to be a
`ToolbarItem(placement: .principal)` — the window's title bar, a different
place from the appearance controls it sits directly above — and **only
Nexus had it**. Exporting code was therefore something you could only do to
the ring in Nexus, so importing a Blender animation into a use case, tuning
it, and taking SwiftUI out the other end meant copying settings back to
Nexus by hand.

It's centered in the pane now, which lands it over the appearance controls
floating at the top of the stage.

Two things it has to keep doing:

- **Both panes stay mounted**, toggled by opacity rather than swapped by a
  `switch`, or the stage's pan/zoom is thrown away on every tab change —
  `ZoomableCanvas` keeps that in an `NSScrollView` with nothing for SwiftUI
  to restore.
- **The tab state belongs to `ContentView`**, one per section, so it
  survives the detail view being rebuilt when the selection changes and so
  the three sections don't share one.

The Cue Library's Code tab is `CueExportView`, not the generic one — a cue
exports as a cue. Use Cases takes its Code pane through an injected
builder, the same trick as the stage, because the exporters' UI is
macOS-only and `UseCaseDetailView` compiles for iOS. Its timeline strip
hides in Code, since a scrubber under exported source says nothing.

## Every section has the same anatomy

Three columns, three detail panes, one shape each.

**Columns** are `ListColumn`: that column's own actions in a bar at the
top, then an optional search field, then the list. The actions were along
the *bottom* first, which is the Finder/Xcode convention for a source list
— but those bars sit at the bottom of a window, and this one sat mid-screen
hard against the timeline strip, reading as part of it rather than as part
of the column. All of it used to
live in the *window* toolbar, because on macOS a `NavigationSplitView`
hoists both `.searchable` and a column's `ToolbarItem`s up there — where
they render right-aligned above the *detail* pane. The Cue Library's search
field therefore sat at the far right of the window, about as far from the
list it filters as the geometry allows, and nothing said which column any
of the Add/Import/Export buttons belonged to. Inside the column is the
Finder/Xcode/Mail convention and makes the association structural.

**Every content column is the same width** (`listColumnWidth()`). They were
200/230/300, 260/300 and 220/260/320, so the column resized every time you
changed section — and the longest subtitle pushed its own section wider
still. Which column is showing shouldn't move the furniture.

**Detail panes** are the stage filling the pane, one strip under it,
controls on the right. Cue Library and Use Cases each used to put a header
block *above* the stage, which made those two canvases shorter than
Nexus's for no reason a person could see.

**The window names the section, and says what it's for.**
`ContentView.sectionTitle`/`sectionSubtitle` feed `navigationTitle` and
`navigationSubtitle` — "Cue Library / 148 cues from the
hardware spec · 3 tweaked", "Use Cases / 69 animations" — which is Mail's
"Inbox — iCloud / All Mail · 628,761 messages, 270 unread" arrangement.

This took four wrong turns and the ending is where it started, so the
whole loop is worth keeping.

On this macOS a `.navigationTitle` renders in a band above the *content
column*, not only in the title bar. Pointed at the **selection** it
restated the row highlighted an inch below it. **Leaving it off doesn't
clear it** — the window falls back to the app's own name, so every section
was headed "Nexus Pod". `.toolbar(removing: .title)` does clear it, but
then that band sits empty and a hand-drawn heading below it looks pushed
down the column, at whatever size we picked rather than the system's.

What was wrong the first time was the *content*, never the mechanism.
Pointed at the **section**, with `navigationSubtitle` saying what the
section is for, that band is exactly the right place — which is what Mail
does. The subtitles are computed in `ContentView` rather than in each
column, because the band belongs to the window and that's where every
store already is.

**A control that stands alone gets its own circle; controls that genuinely
belong together share a capsule** — `ColumnActionGroup`, ruled apart inside
by `ColumnActionDivider`. In Use Cases that's `[+]`, then
`[Blender | pattern folder]` as one control because both bring a design in,
then `[Share]`.

One capsule around everything was tried first and was worse: four
unrelated controls read as one control with four parts, and adding rules
inside only marked where the seams were. Grouping should be visible rather
than inferred from the order.

Three rules for these:

- Buttons inside a group are `.plain`. The capsule is the glass; styling
  them too nests one inside the other.
- Fixed height and font per group, so a heavier or wider SF Symbol can't
  make its control taller than its neighbour.
- Everything is an icon with a tooltip. A labelled button briefly sat
  alongside them and, at a 220pt column, wrapped *one character per line*
  into a capsule taller than the header above it.

Icons alone can't explain themselves, so the **menus** carry it: named for
what they move rather than the verb, under section headers. "Export
Library…" above "Import…" left you to work out they were two ends of the
same JSON file — they read "Export All as JSON…" and "Add from a JSON
File…" under a **Saved Animations** header now. macOS menu items have no
subtitle to hang an explanation on, so the label has to be the
explanation.

What those headers also carried had to go somewhere, and "somewhere" is
the panel whose contents the control acts on:

- The cue's breadcrumb, its **Tweaked** badge and **Reset to Default** are
  at the top of the Cue Library's controls panel — they're about the
  parameters below them.
- **Import Blender…** is at the top of the Use Cases *column*. It was
  briefly in that use case's controls panel, on the reasoning that it acts
  on the selected use case — but it isn't *about* those parameters, it
  replaces most of them, and the top of the column is where an import
  belongs. It posts `.importBlenderIntoUseCase` rather than calling
  directly: the config it writes into is `UseCaseDetailView`'s own
  `@StateObject`, which the column has no reference to. Only the selected
  use case's detail view is mounted, so exactly one listener answers.

### Chrome that leaves the toolbar loses its glass

Both of these regressed the same way and had to be given it back
explicitly: the column action buttons (`ListColumn.actionBar`, now
`.ringGlassButtonStyle()`) and the Preview/Code picker (`DetailPane`, now
`.glassBackground(in: Capsule())`). The system applies Liquid Glass to
toolbar items for free, so anything moved *out* of the toolbar into an
ordinary view silently flattens — the same trade-off `ControlsView` already
notes about moving its cards off `Form`. Worth checking whenever chrome
moves: it doesn't error, it just stops looking like the rest of the app.

Watch for double-glassing too: `ListColumn` styles everything in its
action bar, so a button handed to it must not carry its own
`.ringGlassButtonStyle()` or the effects nest.

### The text-input bug is fixed

The in-column search field is a plain `TextField` and **typing into it
works** — confirmed in the running app. That's the first confirmation that
`Package.swift`'s linker-embedded Info.plist actually cured the standing
text-input bug on this Xcode beta, which means `PasteableTextField`'s own
doc comment is now actionable: every call site can go back to a plain
`TextField` and that file can be deleted. Not done yet.

### The old note, kept for the next time it looks broken

`ListColumn`'s search box is a plain `TextField`, and this app has a
standing text-input bug on this Xcode beta where typing never reaches a
TextField hosted in its own view hierarchy — that's why `PasteableTextField`
exists. The `.searchable` field this replaced was hosted by the *system*
toolbar and may have been working for exactly that reason.
`Package.swift`'s linker-embedded Info.plist was the fix for the underlying
cause and has never been confirmed against a text field. If typing in
search does nothing, check whether the Save Animation dialog's field
accepts typing either: if neither does, it's the old bug and not this
layout.

## What's New

`WhatsNewView` in the core, shown by both apps — Mac presents it from
`ContentView` and iOS from `RootView`, so the two ship the same release
notes rather than two hand-kept copies that drift. Styled after the
system's own post-update screen: title, four or five symbol rows, one
button out.

**The copy in `WhatsNew.current` is placeholder.** It describes work that
actually landed, so it reads as a real release note, but nobody has edited
it for tone or decided what the release is called. Replace it rather than
appending to it — four or five items is the shape Apple uses, and a list
that grows every sprint stops being read.

Two behaviors worth keeping:

- **`WhatsNew.version` gates it**, not the app version. Edit the copy
  without bumping that string and nobody who dismissed the old notes ever
  sees the new ones.
- **It doesn't show on a genuinely fresh install.** Someone opening the app
  for the first time has no idea what's new relative to *what*, and the
  list reads as an unrequested feature tour. First launch records the
  version as seen and shows nothing.

On the Mac it's also under **Help → What's New in Nexus Pod**, posted as a
notification because a `CommandGroup` can't reach into the window's state
directly.

**It scrolls only when it has to** (`ViewThatFits`), and the Mac sheet is
660pt tall rather than 560 because at 560 the five items plus the title
overflowed and it fell back to scrolling — a sheet with its own scroll bar
for content that should just be on screen. That was found by rendering the
view offscreen and looking at it, which is worth knowing how to do:
`ImageRenderer` lays out a `ScrollView`'s content as **empty**, so a screen
that always scrolls renders as a blank page with its buttons. If a rendered
check of this view comes back blank, the content stopped fitting.

## Reset and Add to Timeline, per section

Every Controls card carries two actions in its header, in both panels
(Nexus's `ControlsView` and the one inside `UseCaseDetailView`).

**Reset** restores that section's parameters. Defaults come from a freshly
constructed `RingConfig` rather than literals repeated in
`ControlsSectionReset`, so changing a property's default changes Reset with
it — no second copy to drift. What *can* rot is the section-to-fields
mapping: add a knob to `ShapeSection` and Shape's Reset won't touch it
until it's listed. Two sections deliberately opt out of parts of this:

- **Firmware Fidelity has no Reset at all.** Its controls step an imported
  pattern down through its fidelity levels, and "default" for a recorded
  firmware pattern isn't a meaningful idea.
- **Voice keeps the API key.** It's a credential the user pasted, stored in
  the Keychain; losing it to a mis-click on a section header would be a
  nasty thing for a section reset to do.

**There is no Add to Timeline button on the cards.** There was, briefly,
and it was wrong: a step is a snapshot of the *whole* ring, so the button
did exactly the same thing on every card, and putting one on the Motion
card implied a step that carries only Motion. Adding a step has one home,
the timeline's own **Add Step**.

What that button lost was discoverability — the Controls panel says
nothing about the timeline, and Add Step reads as "add an empty step"
until you know it snapshots the current ring. `AddStepTip` covers it: the
first time any parameter changes, a tip points at Add Step and says what
it keeps.

**Use TipKit, don't hand-roll a callout.** The first version here was
hand-rolled and got wrong both of the things TipKit exists to get right:
it was clipped by the pane's edge — an `.overlay` can't escape its parent's
bounds the way a real popover can — and it sat too low. `.popoverTip` fixed
both without a line of layout code. TipKit also owns "shown once, ever" and
its own datastore, so there's no `UserDefaults` key of ours to keep in
step. It needs `Tips.configure(...)` at launch, done in each app's
`WindowGroup` via `.task` rather than in `init` so a failure can't take
launch down with it.

What did have to stay hand-written is *when* to donate the event.
`ParameterEditWatcher` arms itself a run-loop turn after `watch(_:)`:
binding the config, loading a preset and the first layout pass all
republish it, and any of those would otherwise fire the tip before the user
had touched anything. It stops listening after the first donation rather
than donating on every slider tick.

## Performance: profile it, don't reason about it

The app sat at **100% of a core while idle** on an M2. Two causes, both
found in about five minutes with `sample <pid>` against the running release
build, and neither one guessable:

- **Every list row runs its own animation loop.** Saved Animations, Use
  Cases and every step in the timeline strip render a live `RingView` each,
  and each was driving `TimelineView(.animation)` at full display refresh —
  the whole diode pipeline, sixty times a second, to fill 22 points. With a
  pattern library imported that's seventy of them. They take
  `RingView.thumbnailFrameRate` (12fps) now; at that size it is
  indistinguishable and a fifth of the work.
- **The ripple normalization ran every frame.** `rippleNormalization` is a
  512-point sweep, and each point called `rippleLevel`, which rebuilt the
  drop list from scratch. Together they were ~38% of the main thread on a
  ripple pattern. Both depend only on config, never on elapsed time, so
  both are memoized — static tables, because `RingView` is a struct rebuilt
  every frame with no instance to hang a cache on.

That took the idle profile from 100% of a core to somewhere in the
20-40% range. **Don't quote a single number for this** — `ps` and `top`
disagree because one is a long-run average and the other is instantaneous,
and both depend on which section is showing. An early "~29%" reading here
was taken 44 seconds after launch while the average was still climbing;
a later `ps` on the same build read 65%. Measure the thing you're changing,
not the whole app.

### Measure the pieces, not the process

`swift run -c release PerfCheck` times each part of the UI and reports
milliseconds of main-thread work per second of wall clock, so "20 rows at
12fps" and "one stage ring at 60fps" are comparable. It's a tool, not a
gate — the numbers need a person.

It answered the question sampling couldn't. **A 22pt list row cost the same
as the 200pt stage ring** — 0.98 ms either way — because the work is
SwiftUI view-graph construction, not pixels, and size barely enters into
it. Twenty visible rows at 12fps was 234 ms/s against the stage ring's 62.
The rows were still the dominant cost even after the frame-rate cap.

The fix was to stop building twenty positioned `Circle` views per
thumbnail: a row now draws the same field as a single `AngularGradient`
stroke, the one the smoothing pass added. It keeps the spatial bleed and
skips the persistence taps — without the bleed a lone lit diode out of
twenty is a wedge a few degrees wide, which reads as a speck on a sparse
pattern like the comet. 0.98 ms → 0.38, so twenty rows went 234 ms/s → 86.

Always check the harness floor first: an empty view measures 0.03 ms
through `ImageRenderer`, so these numbers are the view's own cost rather
than the harness's.

Two things deliberately not done:

- `RingConfig.init()` does a synchronous Keychain read and builds a
  `VoiceConversationController`, and every list row makes one. That's a
  launch and scroll cost rather than steady-state CPU, and making it lazy
  means touching the voice pipeline — wrong trade during a pass whose
  measured problem was elsewhere.
- Nothing was changed on the strength of looking clever. The p-norm episode
  in the smoothing section is the cautionary example: measure first, keep
  the number.

## Earmarked: "Snow Leopard" pass

Named for the release that shipped no new features and just made the
existing ones right. These are all known, deliberate gaps rather than
bugs — the reason each was deferred is recorded where the code lives, and
none of them should be picked up piecemeal while feature work continues.

- **Code generator parity.** Done for SwiftUI, outstanding for the other
  three. SwiftUI now exports the full color list (Multi Chase gives each
  its own comet, as in the app), Diode Mode, and all four diode shapes —
  `CodeGeneratorsDiodeMode.swift` ports `RingView.diodeIntensity` field for
  field, drawn into one `Canvas` the way the app's own renderer is.
  `ExportView`'s notice is narrowed to the backends that still lack it
  rather than removed.
  **What `ExportCheck` proves and doesn't.** It compiles all 82 exports —
  every animation type crossed with every diode shape, extra colors, Diode
  Mode on — so a body that doesn't build can't ship. It does *not* prove
  the field computes the same numbers as the app: the two are hand-ported
  copies kept honest by reading them side by side. A differential check
  (compile the export, run it, compare against `diodeIntensity`) is the
  real answer and isn't built. `voiceLevel` is deliberately 0 throughout
  the export — a drop-in file has no microphone, and inventing one would
  be worse than dropping the term.
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
- **Blender's string dispatch.** Half done. `swift run BlenderCheck`
  asserts that every `RingAnimationType` and every `LEDPatternStyle`
  reaches its own branch in the emitted Python rather than the fallback,
  and it's a preflight gate — so a new case can no longer reach a release
  unnoticed. Nothing checked this output before it existed; `ExportCheck`
  covers the SwiftUI exports only.
  It currently reports no gaps, which is the truth. **Its first run
  reported two, and that was the check being wrong, not the generator.**
  A case can dispatch either as `style == "off"` or by sharing a branch
  with its neighbours as `style in ("off", "notApplicable")`, and the
  first matcher only knew the equality form — so it flagged two cases that
  were handled all along, and two unreachable duplicate branches got
  committed on the strength of it. Both forms are recognized now. The
  lesson is the ordinary one: a check that has never failed correctly is
  not yet evidence of anything, and "the tool found a bug" deserves the
  same scepticism as any other claim until the bug is read in the source.
  **Compile-time enforcement is in.** The chains are now generated from
  exhaustive `switch`es in `BlenderDispatch.swift`, so adding a case to
  `RingAnimationType` or `LEDPatternStyle` fails the build (`switch must be
  exhaustive`) until someone writes its Blender body — verified by adding
  a case and watching it break. The bodies moved verbatim: they're pure
  Python with no Swift interpolation, no backslashes and no triple quotes.
  Two deliberate output changes, both verified by diffing the full
  30-script dump before and after:
  - Branch order now follows the enums' declaration order rather than the
    old hand-written order. Safe because every condition is an equality on
    a distinct value, so no branch can shadow another; confirmed by
    comparing the chains as {condition: body} maps.
  - `off` and `notApplicable` used to share one `style in (...)` branch and
    are now two branches with identical bodies. The chain builder merges
    *consecutive* identical bodies and those two aren't adjacent in
    `allCases`. Same output for both, just written twice.
  One trap worth knowing if you touch this again: the emitted Python has
  **two** chains that dispatch on a variable called `style` — the cue
  styles, and easing (`Ease In`/`Ease Out`/`Spring`) up in the helpers. A
  regex looking for `if style ==` finds the wrong one first.
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

### Every pattern replays the device's own command stream

`FirmwarePatternStream` ships each pattern's literal command stream and
replays it. Every scheduler is run once, offline, against a recorder that
captures each `set_color0` / `set_color1` / `select_led` / `select_all_leds`
call with its timestamp — the exact bytes the device receives. Replaying
that is not a reproduction of the animation; it *is* the animation.

This exists because the level-threshold engine below covers 21 patterns and
the other 48 schedule LED commands directly: comets stepping head and tail,
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

### The ring is 20 LEDs

`RingConfig.diodeCount` defaults to 20 and `FirmwarePatternImporter.ringLEDCount`
is 20 — the real hardware count. Note that `pattern_common.py`'s *geometry
constants* still describe a 16-LED ring (`TOP_LEDS = [0, 15]`, 8 symmetric
pairs), which is why this was 16 before the hardware count was known.

Almost everything rescales on its own: the patterns derive their motion from
`TOTAL_LEDS`, so re-recording with `core.TOTAL_LEDS = 20` in
`record_streams.py` is the whole change. 62 of the patterns use the full 20
immediately. **Regenerate both fixtures at the same count** — the
differential check must compare against real Python at 20, never be
re-baselined against the port's own output.

One thing the count change surfaced that is worth carrying forward:

- **A parameter can be *derived* from `TOTAL_LEDS`.**
  `wake_bloom_trio_gaps_green` computes
  `speed_leds_per_s = revolutions_per_loop * TOTAL_LEDS / loop_seconds`,
  which is 4.0 on a 16-ring and 5.0 on a 20-ring. It was ported as the
  literal 4.0 and was the *only* field that broke — silently everywhere
  except `FirmwareFieldCheck`. It's now kept as the expression. If you port
  another field, check whether its constants are literals or derived.

### The app depends on `patterns/` but must not own it

`patterns/` is an *extract* of a firmware repo, not a standalone library: it
imports `led_ring_core` and `ktd2064_ring_model`, which aren't in the folder
and live upstream next to `agw_ringled_patterns_harpy.c`. Vendoring a copy
here would fork the source of truth for the device's behavior, which is a
worse problem than depending on it. So changes to pattern behavior belong
upstream, in the firmware repo — not in this one.

What this repo owns is **provenance**. `firmware-streams.json` and both check
fixtures are generated from one specific state of that library, and without a
record of which, "are our recordings stale?" can only be answered by
re-recording and diffing.

    python3 library_manifest.py verify <patterns-dir>

exits non-zero listing every changed, added and removed file. Run it before a
release; run `write` after re-recording. The manifest is a sha256 per file
plus a combined snapshot id, so a pattern edited upstream and synced down can
never silently invalidate the committed recordings.

### The pattern library was a 16-LED library

`patterns/` had 16 baked into it in three ways, all now derived from
`TOTAL_LEDS` so the library follows the ring instead of assuming one:

- **Geometry constants.** `TOP_LEDS = [0, 15]`, `BOTTOM_LEDS`, the halves
  and `SYMMETRIC_PAIRS`, plus `led_opposite` (`+8`) and `led_mirror`
  (`15 - index`).
- **Counter-rotating starts.** `start_ccw = 15` and `(15 - k) % TOTAL_LEDS`
  in the spin/comet engines and four pattern files — "the far side of the
  ring", written as the index it happened to be.
- **Battery levels.** `_schedule_battery_cascade(..., 4 / 8 / 12)` — 25/50/75%
  of sixteen LEDs, but 20/40/60% of twenty. Now `TOTAL_LEDS // 4`,
  `// 2`, `3 * // 4`, so the pattern means the *fraction* it is named for.
  `battery_100` filled `range(16)`; now `range(TOTAL_LEDS)`. Their
  `DURATION_MS` headers moved with them (7300 / 9800 / 12300 / 16000), since
  a longer ring takes longer to fill at 500 ms a frame.

`ripple.py` declares its own `NUM_LEDS`, asserted against the ring by
`pattern_common`, and is now 20 — which unblocked `listening` and
`ripple_blue_white`. **Coverage at 20 is 69 of 69 exact.**

Because the fill argument is now an expression rather than a literal,
`FirmwarePatternImporter.batteryFillCount` evaluates the
`[k *] TOTAL_LEDS // d` shapes instead of scraping a digit. A digit still
works, for anything written the old way.

### Bulk import: a whole library into Use Cases

`UseCaseListView`'s "Import Pattern Folder…" creates one use case per `.py`
file, each with its palette, timings and phase steps. Everything routes
through `BlenderScriptImporter.apply`, so a bulk import and a single import
cannot drift — same reading, same streams, same timelines. Files that aren't
patterns apply nothing and are skipped by name in the summary rather than
becoming empty use cases.

The single-file button in `UseCaseDetailView` imports *into* the use case
you're editing, which is right for reworking one animation and wrong for
taking delivery of sixty-nine.

### Timeline steps are windows into the stream, not re-creations

A phased pattern holds the recorded stream on *every* step, each with
`RingConfig.firmwarePatternStreamOffset` set to where that phase begins.
Without it the two halves of an import contradict each other: the config
replays the real thing while every step holds a hand-built approximation of
the same phase, so selecting a step quietly swapped exact for approximate.

The offsets are a genuine cross-check. They're just the running sum of the
step durations, and for `spotlight_deterrence` they land on 0.5 / 4.0 / 6.5 /
11.0 / 14.5 — exactly the `t_white_on` / `t_ramp` / `t_steady` /
`t_break_start` / `t_alarm_start` computed in the Python. The phases derived
by hand and the recorded stream agree.

Three precedence rules make this actually render, and each one was a bug
first:

- **A stream outranks `patternStyle`.** `effectivePatternStyle` returns nil
  when a stream is set. `patternStyle` short-circuits the whole diode path —
  it renders via `LEDCuePreviewView` — so a step that was both a stream
  window and a named spec-sheet style drew the style and never reached the
  stream. Steps carry both on purpose: the style is the fallback once you
  step down off the stream.
- **A stream step gets `localTime`, not `phaseTime`.** `phaseTime` exists to
  keep the ring's *angle* continuous across a boundary; a recorded stream has
  no angle to keep continuous, and its events carry absolute timestamps.
  Feeding it the rotation offset indexed into an unrelated part of the stream
  and rendered as a blank ring partway through playback.
- **`_import_ripple_math` needs its parentheses.** Every pattern lists it in
  the bulk `from pattern_common import (...)` line, so matching the bare name
  typed a dozen unrelated patterns — a shimmer, a lattice, a spotlight — as
  Ripple. Only a *call* means the pattern uses the engine.

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

**Coverage: 69 of 69 exact at 20 LEDs.** The ripple family needed `ripple.py` — the
canonical motion maths `pattern_common._import_ripple_math()` looks for —
which isn't in `patterns/`. `record_streams.py` adds the Desktop to
`sys.path` to find it; point that at wherever it lives if it moves.

`ripple_green` is the one pattern that isn't two palette registers. It is
**snapshot-native**: `build_ripple_green_steps` authors `RingStep[]` carrying
a per-LED `(r, g, b, brightness)` field, played through the step player. The
recorder folds the brightness into each LED's color and emits it as event
kind 6, an explicit per-LED RGB, because that is what the LED actually emits.
Any future per-LED-brightness pattern records the same way with no new
format.

Two structural rules earn their keep here:

- **A pattern that imports the ripple maths is a ripple**, whatever it calls
  itself. `listening.py` is a re-tuned ripple whose `DESCRIPTION` reads
  "voice-assistant listening feedback (blue water + white glimmers)" and
  never uses the word — by keyword alone it matched nothing and imported as
  the default Wave.
- **The ripple engine's knobs are whitelisted locals** (`n_drops`,
  `ripple_speed`, `decay_rate`, `pulse_w`), so even without a stream these
  map onto Drop Count, Speed, Decay and Front Width.

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

## One stage, three sections

`RingStage` (macOS target) is the canvas every section previews on: the
pannable, zoomable phone mockup filling the pane, with Large Preview
floating over it as a draggable card, plus the light/dark toggle. It was
Nexus's and only Nexus's — the Cue Library and Use Cases each had a ring in
a scrolling column, so the app had one good preview and two approximations,
and which you got depended on which list you'd clicked.

The timeline strip deliberately stays *out* of the stage. The Cue Library
has no player, and an empty scrubber would invent a concept that section
doesn't have.

Two seams worth knowing:

- **Use Cases injects the stage.** `UseCaseDetailView` lives in the core
  (it needs `ControlsSections.swift`'s internal section structs) and so
  compiles for iOS, while the stage is AppKit all the way down —
  `ZoomableCanvas` wraps a real `NSScrollView`. So it takes a
  `StageBuilder` closure; the macOS app passes `RingStage` in, and anything
  that can't falls back to the centered ring it had before.
- **The Cue Library converts to a `RingConfig`.** The stage speaks
  `RingConfig`, so `LEDCueParameters.apply(to:)` — which used to be private
  to `LEDCuePreviewView`, for handing continuous cues to `RingView` — is
  public and does the whole job. Not a second conversion written to look
  like the first.

`apply(to:)` copies `lineWidth` **only for `.continuousAnimation`**. That's
the one style whose stroke is really the cue's own; every other style takes
`lineWidth` as a separate `LEDCuePreviewView` init parameter because it's
meant to vary with the chrome, not the cue. Copying it regardless made the
pattern styles about three times too thick: `RingView` reads
`config.lineWidth` as *pod-relative* and multiplies by `size /
referenceDiameter`, so a cue's 12 — authored against a ~160pt preview —
became a 39pt stroke on a 190pt ring. Measured, not guessed: a render
harness put `solid` at 34% mean pixel difference from the old preview
before the fix and 21% after, with the remainder being the app's house ring
proportion, which is the point of sharing a stage.

### Part B: hoist the state, not the stage

Sections swap through a `switch` in `ContentView`, and a `switch` gives each
branch its own identity — so SwiftUI tears the stage down and rebuilds it on
every section change. `ZoomableCanvas` keeps its pan and zoom in a real
`NSScrollView`, with nothing for SwiftUI to restore, so the canvas reset
every time you changed section.

The plan had been to hoist the whole stage into `ContentView` and feed it
whichever config is selected. That works, but it only works by *first*
hoisting every section's editing state — the cue's parameters, the use
case's config and its own `TimelinePlayer`, and the reload-on-selection
that `.id(preset.id)` currently gets for free — because one stage needs one
resolved input. A large change to the thing most likely to break quietly.

`StageState` gets the same result for much less: it holds what the stage
*keeps* rather than what it *shows* — zoom, pan, appearance, which corner
Large Preview is parked in — and `ContentView` owns one and hands it to all
three sections. The view can now be rebuilt as often as SwiftUI likes and
comes back exactly as it was. The `StageBuilder` seam stays, which is fine:
it's what lets the core-hosted `UseCaseDetailView` still compile for iOS.

Two things about it:

- **`magnification` and `scrollOrigin` are not `@Published`.** They're
  written continuously through a pinch or a scroll; publishing would
  invalidate the stage on every frame of a gesture, and nothing needs to
  react to them. They're storage, read once when the canvas is rebuilt.
- **The scroll restore happens twice, the second time deferred.** At
  `makeNSView` the scroll view has a document view but not its final frame,
  and `CenteringClipView` re-centers whatever it is given until the content
  is genuinely larger than the viewport — so the first call is usually
  clamped straight back to centre. The deferred repeat lands after the
  first layout pass, and only ever runs at creation, so it can't fight a
  scroll in progress.

## Taking delivery of a whole library

`PatternFolderImport` (in the core, not in a view) is the folder importer
both macOS entry points run: the **Import Patterns** button in Use Cases,
and **Import Pattern Library → Use Cases…** in Nexus's Share menu. It
creates one use case per file and *replaces by name*, keeping the existing
id so the use case's timeline file — which is keyed by that id — is
overwritten in place instead of orphaned.

It lands in Use Cases from both buttons, deliberately. A saved animation in
Nexus is a bookmark of `config` alone and the Nexus timeline is one shared
document, so the twenty-one multi-phase patterns would arrive there with
their steps silently dropped. A use case owns a timeline keyed by its id,
which is the only place a library can arrive intact. The Nexus menu item
says where the result goes rather than quietly sending it elsewhere.

Two things the scan has to know:

- **It's recursive.** A library arrives as a zip, and where the scripts end
  up depends on who expanded it. A flat scan of the folder you were looking
  at reported "no .py files in that folder" with the scripts one level down.
- **`._foo.py` is not a Python file.** It's an AppleDouble sidecar — `foo.py`'s
  resource fork and xattrs, split out because the archive can't carry them
  inline. Binary, ends in `.py`, one beside every real script. Recursion
  without that exclusion imports the library twice, once correctly and once
  as garbage.

They were in the shipped zip because `package_patterns.sh` used `ditto
--sequesterRsrc`, which *writes* them — every file here comes out of iCloud
carrying the same `com.apple.FinderInfo` that breaks codesign. Now
`--norsrc --noextattr --noqtn`: these are plain text files whose resource
forks carry nothing anyone wants.

### `swift run ImportCheck`

Runs the real import path over the library headlessly and reports what each
file produced. It exists because "the import is broken" is a claim about a
code path that normally only runs behind a file picker, in a signed app,
against files in iCloud — and every part of that makes the answer
ambiguous. A file that imports nothing looks exactly like a file the app
couldn't read, which looks exactly like an app that never reloaded (see
"Verifying you're testing what you think you are"). Currently **69 patterns,
69 exact, 21 phased**. It's a preflight gate.

It has to know the same two discriminators the importer does: a pattern
defines `schedule_<name>`, and `pattern_common.py` defines the `_schedule_*`
helpers every pattern calls. Importing nothing from the library is correct,
not a failure — miss that and it reads as the one file that broke.

## Smoothing — the same animation, app-shaped

Everything else in this app exists to be *accurate*: quantized ticks, two
palette registers, hard-thresholded levels, twenty pixels that are on or
off. `RingConfig.smoothingEnabled` is the other direction — soft edges and
persistence, so a pattern reads as design rather than as a driver.

It's a **treatment, not a different animation**. It takes whatever the diode
field already produced — recorded stream, ported firmware field, or one of
this app's own types — and spreads it in space and trails it in time. One
implementation, applying to all 69 imported patterns at once, and switching
it off returns the hardware-exact render pixel for pixel.

Three things worth not rediscovering:

- **Decaying max, never a weighted average.** An average dims a lone lit
  diode to a fraction of itself — blur a single pixel and you get a smudge,
  not a glow. Taking the strongest neighbouring contribution, attenuated by
  distance, keeps the peak exactly where it was and adds falloff around it.
  Same over time: the head of a comet stays at full brightness and only the
  tail decays. Both passes carry the *contributor's* color, so a trail is
  the hue of the head that left it.
- **No frame-to-frame state.** `RingView` is a pure function of elapsed
  time, which is what makes scrubbing, timeline playback and frame export
  agree. Persistence resamples the field at earlier instants instead of
  accumulating. That also buys the soft *rise*: there's no "next frame" to
  wait for, just another instant to evaluate, so it samples slightly
  forward too.
- **It costs 0.45 ms/frame** (release, 20 diodes, 9 taps, measured against
  1.38 ms for the hardware path). No optimization needed; don't add a cache.

### Gradient ring

Smoothing the *field* wasn't enough on its own. Each diode got a soft,
blended level and color — and was then drawn as one of twenty separate
circles with gaps between them, so a gradient computed across dots still
read as dots with halos. The maths went fluid and the picture didn't.

`smoothingGradientRing` strokes the ring as a single `AngularGradient` with
a stop per diode instead, letting SwiftUI interpolate between them. Same
field, same controls, continuous ring. On by default, because "Smooth"
without it is the half of the effect that doesn't show; off returns the
twenty diodes.

Two things that are load-bearing:

- **`startAngle` is -90°.** Diode 0 sits at twelve o'clock (`diodeLayer`
  places it at `-.pi / 2`) while an `AngularGradient` starts at three. Get
  it wrong and every pattern is rotated a quarter turn, which reads as a
  timing bug rather than a geometry one.
- **The last stop repeats the first diode's color at location 1.** Without
  it the gradient runs from diode 19 back to diode 0 across a zero-width
  span and draws a hard seam at twelve o'clock — most visible on exactly
  the patterns this mode is for.

### Measuring flicker

"It flickers a bit, depending on the setting" is not something a contact
sheet can answer, and the obvious metric is the wrong one. Mean frame
brightness barely moves on a comet however badly its tail stutters — the
total light is roughly constant, it's just in different places.

What works: sample the rendered ring at each diode's own angular position,
build a per-diode trace over a couple of seconds at 60fps, and count
**reversals** — a diode that rises then falls (or the reverse) by more than
about 2% in consecutive frames. That's the signature of stutter, as opposed
to a smooth rise or fall. Track the worst single-frame **step** alongside
it, because the two trade against each other and a change that removes all
the reversals by removing the look-ahead just converts them into pops.

Doing that turned a vague report into three specific findings:

- The flicker was confined to sparse patterns (a comet) at wide bleed and
  long persistence. Solid patterns never flickered at any setting.
- **Frame-aligned taps are worth having.** Sampling the stream's own
  boundaries rather than evenly spaced instants took the comet from 6
  reversals to 2 at the default and 32 to 18 at the extreme.
- **The forward look-ahead was the main cause**, and capping it at 120 ms
  rather than scaling it with persistence took the extreme from 18
  reversals to 2 while leaving the default untouched. 80 and 100 ms were
  both worse at the default without being better at the extreme.

Also settled by measuring: a **p-norm soft max** in place of the hard max
looked like the principled fix for "the winner keeps changing" and was
much worse — contributions accumulate, so every pattern with light on most
diodes brightened and dimmed as taps entered and left the window. The
rainbow went from zero reversals to 31. The max stays.

Preview only — the code generators still emit the hardware render, and the
Smooth card's footer says so.

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

## Verifying you're testing what you think you are

Three times now this project has produced a "bug" that was really a stale
artifact, each costing more than the real fix would have. The setup makes it
easy, so check these first when the running app contradicts a check that
passes against the module:

- **Duplicate bundle ids.** `/Applications/Nexus Pod.app` and
  `/Applications/RingAnimator.app` both claim `ringanimator.RingAnimator`, and
  so does any dev bundle you assemble. `open` can resolve to one you didn't
  mean.
- **`open` reactivates rather than relaunches.** If the old process is still
  alive, `open` on a freshly built bundle just brings the old one forward,
  still running its old code. And `pkill -f "Nexus Pod (dev)"` does *not*
  kill it: `-f` takes an extended regex, so `(dev)` is a capture group
  matching bare `dev`, which the command line doesn't contain. Match on a
  path fragment instead — `pkill -f 'Developer/Nexus'` — and confirm with
  `pgrep`.
- **Local state outlives the build that wrote it.**
  `~/Library/Application Support/RingAnimator/` holds `use-cases.json` and a
  timeline file per use case. One written by an older binary is
  indistinguishable from a current one, and reading it produced a convincing
  but entirely false conclusion that the importer had stopped setting a field
  — the importer was fine; the file predated the fix.

So: `ps aux | grep` the executable path, compare its mtime to your last
build, and clear Application Support before an import test. A harness
compiled against `out/Products/{Debug,Release}` answers "what does the code
do?" without any of this ambiguity, and disagreeing with the app is a signal
about the *app's* state, not the code's.

### Don't run two preflights at once

Every step writes into `$SCRATCH`. The swift builds take SwiftPM's own lock
and merely wait; `xcodebuild` has no such protection, and two of them into
one `SYMROOT` fail whichever loses — which prints `✗ RingAnimatoriOS` and
reads as a broken iOS target. It happened once here, and building the same
target directly a minute later succeeded, which is the tell.

`preflight.sh` now takes a `mkdir` lock and refuses to start a second run.

## Open items (not yet done)

- **TestFlight app name**: TestFlight was still showing an old app name to
  testers. This is a separate App Store Connect metadata field ("App
  Information → Name" at appstoreconnect.apple.com), independent of the
  binary's `CFBundleDisplayName` — not fixable from Xcode or this repo.
  Needs a manual edit in the App Store Connect web portal. Unconfirmed
  whether this has been done yet.
- **Local test data**: `~/Library/Application Support/RingAnimator/` holds
  local `saved-presets.json`/`use-cases.json` on the dev machine — currently
  the 69 imported firmware patterns. This is *not* shipped (confirmed —
  `RingPresetStore` has no seed data, `SavedPresetsView`/`UseCaseListView`
  have correct empty states), it's purely local state. A recipient opens the
  app empty and runs Import Pattern Folder themselves.
- **Drawing diodes changed the `.bar` shape's look.** `diodeLayer` draws
  into one `Canvas` now instead of building twenty positioned views. Round,
  square and segment are identical to within antialiasing (0.6-1.8% mean
  pixel difference); `.bar` measured 6% and is visibly *cleaner* — at 1.9
  aspect twenty bars overlap heavily, and as separate views their
  antialiased edges accumulated into a bright patch and an inward wash that
  a single fill doesn't produce. Better, but a change; worth an eye on if
  anyone was fond of the old look.
- **Two stale copies in `/Applications`** share the bundle id
  `ringanimator.RingAnimator`: `Nexus Pod.app` (2.0) and `RingAnimator.app`
  (1.0, the old name). LaunchServices can resolve `open` to the wrong one —
  that cost an hour of chasing a phantom bug once, reading behavior from a
  binary that predated the change under test. Deleting the 1.0 copy removes
  the ambiguity.
- **The pattern library's edits aren't upstream yet.** `patterns/` is an
  extract of a firmware repo (see "The app depends on `patterns/` but must
  not own it"), and the 20-LED corrections currently exist only in iCloud.
  They're firmware-behavior changes and belong in that repo, reviewed.
  Until then `library_manifest.py` at least pins which snapshot the
  committed recordings came from.

## Git

**There is a remote now**: `git@github.com:henslin/nexus-pod.git`. This
section used to say there wasn't, and that rewriting local history was
safe — it isn't any more for anything that has been pushed. `origin/master`
was last seen at `2b0eb8b`, a long way behind, so most local commits are
still unpushed and still safe to amend; check `git log origin/master..HEAD`
before rewriting anything. Latest commits, most recent first:
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
