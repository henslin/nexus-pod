import SwiftUI

/// One swatch in the app's approved brand color palette — see
/// `ApprovedColorPalette`. `hex` (not the resolved `Color`) is what gets
/// compared against a `ColorPicker`'s current selection to decide whether
/// a swatch should show as "currently picked", the same hex-string
/// identity `RingPreset`/the code exporters already treat colors by.
struct ApprovedColor: Identifiable {
    let name: String
    let hex: String

    var id: String { hex }
    var color: Color { Color(hex: hex) }
}

/// A curated subset of the design team's full brand color sheet — just the
/// named accent/brand colors, skipping the near-duplicate grays (Fade-Away
/// Gray/Silver/Mist/Cloud Gray all read as "off-white" or "light gray" at
/// swatch size) and the Dark Mode variants (this is a tap-to-apply quick
/// pick, not a full palette browser — the ring's own Light/Dark toggle
/// already covers appearance). Shown next to `ColorSection`'s Primary/
/// Secondary `ColorPicker`s (`ControlsSections.swift`) so picking an
/// approved color doesn't require opening the system color picker; shared
/// by both the Mac Controls panel and the iOS settings menu since they
/// both build on the same `ColorSection`.
enum ApprovedColorPalette {
    static let colors: [ApprovedColor] = [
        ApprovedColor(name: "Midnight Blue", hex: "#03374F"),
        ApprovedColor(name: "Sky Blue", hex: "#055E88"),
        ApprovedColor(name: "Sea Blue", hex: "#2288DD"),
        ApprovedColor(name: "Cautious Yellow", hex: "#F8B541"),
        ApprovedColor(name: "Warning Red", hex: "#D22434"),
        ApprovedColor(name: "Spring Green", hex: "#33CC99"),
        ApprovedColor(name: "Stark White", hex: "#FFFFFF"),
        ApprovedColor(name: "Jet Black", hex: "#404040"),
    ]
}
