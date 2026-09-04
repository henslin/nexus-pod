// swift-tools-version:6.1
import Foundation
import PackageDescription

// `swift build`/Xcode's ⌘R both link the `RingAnimator` executable as a
// bare Mach-O binary — SwiftPM has no manifest-level mechanism to give an
// executableTarget a real Info.plist the way an Xcode app target gets one
// "for free". Without it, the process launches with no CFBundleIdentifier
// at all, which is the suspected root cause behind two previously-parked
// bugs: trackpad pinch-to-zoom never firing (see
// `Sources/RingAnimator/Views/ZoomableCanvas.swift.bak`) and text input
// never reaching any TextField/SecureField in a debug run (see the
// workaround in `Sources/RingAnimatorCore/Views/ControlsSections.swift`).
// Console logs seen during zoom debugging ("Cannot index window tabs due
// to missing main bundle identifier") point the same direction.
//
// The fix: embed the exact same `Packaging/Info.plist` already used for
// the signed release build directly into the debug binary via a linker
// section (`__TEXT,__info_plist`) — the standard trick command-line/
// SwiftPM-built macOS apps use to get a real bundle identity without a
// full `.app` wrapper. This makes `swift run`/Xcode's ⌘R finally match
// what `Packaging/build_and_sign.sh` produces, instead of testing against
// two different bundle configurations. `#filePath` (not a relative
// string) so the path resolves correctly no matter who invokes the
// linker — Xcode's build happens from a DerivedData directory, not this
// package's own folder.
private let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
private let infoPlistPath = packageDirectory.appendingPathComponent("Packaging/Info.plist").path

let package = Package(
    name: "RingAnimator",
    // The `.v26` *enum case* genuinely doesn't exist in this Xcode beta's
    // `PackageDescription` — but the string initializer does, and it works.
    // That distinction matters more than it looks: the deployment target
    // recorded in the binary is what makes macOS draw an app with the
    // current control appearance rather than the legacy one. Built at
    // macOS 14, every system control — toggles above all — rendered in
    // compatibility style no matter what the SwiftUI code asked for, and
    // no amount of `.glassEffect` at call sites could change it. Confirmed
    // with `vtool -show-build`: minos 14.0 before, 26.0 after.
    //
    // The `#available(macOS 26.0, *)` checks throughout are now always
    // true. They're harmless and left in place; collapsing them is
    // cleanup, not a fix, and worth doing deliberately rather than as a
    // side effect of this.
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [
        // Exposes the shared core to other Xcode projects (e.g. the iOS
        // app) via a local Swift Package dependency.
        .library(
            name: "RingAnimatorCore",
            targets: ["RingAnimatorCore"]
        )
    ],
    targets: [
        // Shared, platform-agnostic core: models, the ring renderer, the
        // controls form, and the SwiftUI/Compose code exporters. Both the
        // macOS design tool and the iOS app build on top of this.
        .target(
            name: "RingAnimatorCore",
            path: "Sources/RingAnimatorCore",
            resources: [
                .process("Resources")
            ]
        ),
        // Generates every SwiftUI export and typechecks it — see the
        // header comment in Sources/ExportCheck/main.swift. Not part of
        // the app; `swift run ExportCheck` before a release.
        .executableTarget(
            name: "ExportCheck",
            dependencies: ["RingAnimatorCore"],
            path: "Sources/ExportCheck"
        ),
        // Verifies every ported firmware level field still matches the
        // real Python sample for sample — see the header comment in
        // Sources/FirmwareFieldCheck/main.swift. Not part of the app;
        // `swift run FirmwareFieldCheck` before a release.
        .executableTarget(
            name: "FirmwareFieldCheck",
            dependencies: ["RingAnimatorCore"],
            path: "Sources/FirmwareFieldCheck",
            exclude: [
                "firmware-levels.json", "firmware-frames.json",
                "dump_reference.py", "record_streams.py",
            ]
        ),
        // Runs the real import path over a folder of pattern scripts and
        // reports what each one produced — see the header comment in
        // Sources/ImportCheck/main.swift. Not part of the app;
        // `swift run ImportCheck` when an import looks wrong.
        .executableTarget(
            name: "ImportCheck",
            dependencies: ["RingAnimatorCore"],
            path: "Sources/ImportCheck"
        ),
        // Dumps and checks the Blender exports — see the header comment in
        // Sources/BlenderCheck/main.swift. Not part of the app;
        // `swift run BlenderCheck` before a release.
        .executableTarget(
            name: "BlenderCheck",
            dependencies: ["RingAnimatorCore"],
            path: "Sources/BlenderCheck"
        ),
        // Times each piece of the UI so "what should I optimize" has an
        // answer with units — see the header comment in
        // Sources/PerfCheck/main.swift. A tool, not a gate: the numbers
        // need a person to read them. `swift run -c release PerfCheck`.
        .executableTarget(
            name: "PerfCheck",
            dependencies: ["RingAnimatorCore"],
            path: "Sources/PerfCheck"
        ),
        .executableTarget(
            name: "DiffCheck",
            dependencies: ["RingAnimatorCore"],
            path: "Sources/DiffCheck"
        ),
        // Every branch of the bundled-library sync, including the ones
        // whose correct behaviour is "leave it alone" — see the header
        // comment in Sources/SyncCheck/main.swift. `swift run SyncCheck`.
        .executableTarget(
            name: "SyncCheck",
            dependencies: ["RingAnimatorCore"],
            path: "Sources/SyncCheck"
        ),
        // Proves a transparent export really carries alpha all the way to
        // the file — see the header comment in Sources/AlphaCheck/main.swift.
        // Not part of the app; `swift run AlphaCheck` before a release.
        .executableTarget(
            name: "AlphaCheck",
            dependencies: ["RingAnimatorCore"],
            path: "Sources/AlphaCheck"
        ),
        // macOS design tool: sidebar controls + tab bar mockup + code export.
        .executableTarget(
            name: "RingAnimator",
            dependencies: ["RingAnimatorCore"],
            path: "Sources/RingAnimator",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", infoPlistPath
                ])
            ]
        )
    ]
)
