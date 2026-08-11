// swift-tools-version:6.1
import PackageDescription

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
            path: "Sources/RingAnimator"
        )
    ]
)
