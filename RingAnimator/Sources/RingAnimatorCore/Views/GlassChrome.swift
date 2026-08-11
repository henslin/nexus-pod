import SwiftUI

/// Real Liquid Glass background for standalone app chrome — floating
/// pills, hint labels, and cards that sit directly on a canvas rather than
/// inside a `List`/`Form`/toolbar (those already render with System-applied
/// Liquid Glass automatically; see `ringGlassButtonStyle()`'s doc comment
/// in `ControlsSections.swift` for the fuller version of this point).
///
/// Mirrors that same helper's `#available` fallback: a real
/// `.glassEffect(.regular, in:)` on macOS/iOS 26, `.regularMaterial` below
/// that — the same shape `ControlsView`'s private `cardBackground()` uses,
/// pulled out here as a public, reusable modifier once other standalone
/// chrome (`PhoneMockupView`'s controls pill and zoom hint, `ContentView`'s
/// Large Preview card) needed the identical treatment. `ControlsView`
/// keeps its own private copy rather than switching to this one — it
/// predates this file and touching working, already-verified code purely
/// to deduplicate a five-line `#available` check isn't worth the risk.
public extension View {
    @ViewBuilder
    func glassBackground<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }
}
