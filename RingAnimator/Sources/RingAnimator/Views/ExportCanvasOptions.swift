import SwiftUI
import RingAnimatorCore

/// What the frame contains — shared by every GIF/movie export sheet.
///
/// One type and one control group rather than a copy in each sheet: these
/// options went into the single export first and were immediately wanted
/// in the batch one, and two hand-maintained copies of six controls drift
/// the moment a seventh is added.
@MainActor
struct ExportCanvasSettings: Equatable {
    /// Light by default, rather than inherited from the canvas: an export
    /// usually lands in a deck or a doc, and those are light far more often
    /// than the tool you made it in.
    var appearance: ColorScheme = .light
    var transparent = false
    var includeAppUI = false
    var tab: DemoTab = .dashboard
    /// `nil` is no phone around the screen. One control instead of a
    /// toggle plus a colour picker — "no frame" is just another choice of
    /// frame, and splitting it across two rows made you set two things to
    /// express one.
    var deviceFinish: AnimationExporter.DeviceFinish?

    var canvas: AnimationExporter.Canvas {
        guard includeAppUI else { return .ring }
        return .appUI(tab: tab, device: deviceFinish)
    }

    /// A bare phone screen is opaque edge to edge, so there's nothing for
    /// transparency to keep. Framed, there is: the rounded corners.
    var transparencyUnavailable: Bool {
        includeAppUI && deviceFinish == nil
    }

    var effectiveTransparent: Bool {
        transparent && !transparencyUnavailable
    }

    var pixelSize: CGSize {
        let size = AnimationExporter.canvasSize(canvas)
        return CGSize(
            width: size.width * AnimationExporter.renderScale,
            height: size.height * AnimationExporter.renderScale
        )
    }
}

struct ExportCanvasOptionsView: View {
    @Binding var settings: ExportCanvasSettings
    /// Emitted as `Section`s so both export sheets can put them in a
    /// grouped `Form` — the controls had grown to nine in one flat stack,
    /// where nothing said which of them changed the picture and which
    /// changed the file.
    var body: some View {
        Section("Background") {
            // Its own section: it isn't a peer of GIF and Movie — those
            // say which files to write, this says what's behind the ring.
            Toggle("Transparent background", isOn: $settings.transparent)
                .toggleStyle(.checkbox)
                .disabled(settings.transparencyUnavailable)
            if settings.transparencyUnavailable {
                Text("A full app screen has no transparent edges to keep.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Section("Appearance") {
            Toggle("Include UI", isOn: $settings.includeAppUI)
                .toggleStyle(.checkbox)

            // Present but inactive rather than absent, so the choice is
            // visible before it applies — a control that appears out of
            // nowhere is a control you didn't know you had.
            Picker("Tab", selection: $settings.tab) {
                ForEach(DemoTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .disabled(!settings.includeAppUI)

            Picker("Mode", selection: $settings.appearance) {
                Text("Light").tag(ColorScheme.light)
                Text("Dark").tag(ColorScheme.dark)
            }
            .pickerStyle(.radioGroup)
        }

        Section("iPhone") {
            // A menu is right for a finish: one colour standing in for the
            // rest is what its closed state should show.
            Picker("Device Frame", selection: $settings.deviceFinish) {
                Text("None").tag(AnimationExporter.DeviceFinish?.none)
                ForEach(AnimationExporter.DeviceFinish.allCases) { finish in
                    Text(finish.rawValue).tag(AnimationExporter.DeviceFinish?.some(finish))
                }
            }
            .disabled(!settings.includeAppUI)

            if settings.includeAppUI {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("A phone frames the app screen, so it needs Include UI.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var note: String {
        let size = settings.pixelSize
        let dimensions = "\(Int(size.width))×\(Int(size.height))"
        if settings.deviceFinish != nil {
            return "Exports the phone at \(dimensions). Turn on Transparent background to keep the rounded corners clear instead of filled."
        }
        return "Exports the phone screen at \(dimensions), square-cornered, ready to drop into a device frame. The screen is opaque, so there's no transparency to keep."
    }
}
