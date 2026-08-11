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
    // Neither `.v26` nor `.v27` are available as `SupportedPlatform` cases
    // in this Xcode beta's `PackageDescription` — bumping the declared
    // swift-tools-version didn't unlock them either, so this genuinely
    // appears to be a gap in the beta's SwiftPM support rather than a
    // manifest-version ceiling. Back to the known-good baseline: the
    // package's minimum stays low, and every real Glass API call site
    // (TabBarPreview.swift, ExportView.swift) goes back to an explicit
    // `#available(macOS 26.0, *)` check with a pre-Glass material fallback,
    // same as before the "drop the fallback" pass. The separate iOS Xcode
    // project isn't affected by this — its deployment target is set
    // directly in project settings (27.0), not through this file, so
    // RootView.swift's glass calls there can stay unconditional.
    platforms: [.macOS(.v14), .iOS(.v17)],
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
