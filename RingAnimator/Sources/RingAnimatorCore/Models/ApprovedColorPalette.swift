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

/// "App Hues" — the design team's full brand color sheet, exactly as
/// handed off (all 18 swatches, grays and Dark Mode variants included).
/// Shown next to `ColorSection`'s Primary/Secondary/additional
/// `ColorPicker`s (`ControlsSections.swift`) so picking an approved color
/// doesn't require opening the system color picker; shared by both the
/// Mac Controls panel and the iOS settings menu since they both build on
/// the same `ColorSection`.
enum ApprovedColorPalette {
    static let colors: [ApprovedColor] = [
        ApprovedColor(name: "Midnight Blue", hex: "#03374F"),
        ApprovedColor(name: "Sky Blue", hex: "#055E88"),
        ApprovedColor(name: "Stark White", hex: "#FFFFFF"),
        ApprovedColor(name: "Fade-Away Gray", hex: "#F7F7FA"),
        ApprovedColor(name: "Silver", hex: "#F2F2F6"),
        ApprovedColor(name: "Mist", hex: "#E8E8EB"),
        ApprovedColor(name: "Cloud Gray", hex: "#C6C6CF"),
        ApprovedColor(name: "Stone", hex: "#8E919E"),
        ApprovedColor(name: "Charcoal", hex: "#636466"),
        ApprovedColor(name: "Jet Black", hex: "#404040"),
        ApprovedColor(name: "Sea Blue", hex: "#2288DD"),
        ApprovedColor(name: "Cautious Yellow", hex: "#F8B541"),
        ApprovedColor(name: "Warning Red", hex: "#D22434"),
        ApprovedColor(name: "Spring Green", hex: "#33CC99"),
        ApprovedColor(name: "Sky Blue (Dark Mode)", hex: "#0E8DC8"),
        ApprovedColor(name: "Sea Blue (Dark Mode)", hex: "#4A90E2"),
        ApprovedColor(name: "Cautious Yellow (Dark Mode)", hex: "#FCBD4F"),
        ApprovedColor(name: "Warning Red (Dark Mode)", hex: "#F04254"),
    ]
}
