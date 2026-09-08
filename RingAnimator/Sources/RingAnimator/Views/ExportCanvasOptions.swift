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
        Section("Appearance") {
            // Radios, not a menu: "ring" and "app screen" are different
            // kinds of output, and a menu shows you one of them while
            // hiding the other behind a click.
            Picker("Include UI", selection: $settings.includeAppUI) {
                Text("Ring only").tag(false)
                Text("App screen").tag(true)
            }
            .pickerStyle(.radioGroup)

            if settings.includeAppUI {
                // A menu is right here: the tabs are four of the same kind
                // of thing, and the list would otherwise crowd out the
                // choices that change the shape of the export.
                Picker("Tab", selection: $settings.tab) {
                    ForEach(DemoTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
            }

            Picker("Mode", selection: $settings.appearance) {
                Text("Light").tag(ColorScheme.light)
                Text("Dark").tag(ColorScheme.dark)
            }
            .pickerStyle(.radioGroup)
        }

        // Only with the app screen: the frame wraps a screen, and there
        // isn't one to wrap around a bare ring.
        if settings.includeAppUI {
            Section("iPhone") {
                // A menu *is* right for this one — it's a finish, and one
                // colour standing for the rest is exactly what it shows.
                Picker("Device Frame", selection: $settings.deviceFinish) {
                    Text("None").tag(AnimationExporter.DeviceFinish?.none)
                    ForEach(AnimationExporter.DeviceFinish.allCases) { finish in
                        Text(finish.rawValue).tag(AnimationExporter.DeviceFinish?.some(finish))
                    }
                }
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
