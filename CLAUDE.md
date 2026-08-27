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
