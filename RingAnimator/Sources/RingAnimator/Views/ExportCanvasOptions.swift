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

/// GIF, movie, or both. A selection rather than two switches — but with
/// "Both" kept, because writing one of each in a pass is a real thing to
/// want and a picker of two would have quietly removed it.
enum ExportFileFormat: String, CaseIterable, Identifiable {
    case gif = "GIF"
    case movie = "Movie"
    case both = "Both"

    var id: String { rawValue }
    var wantsGIF: Bool { self != .movie }
    var wantsMovie: Bool { self != .gif }
}

struct ExportCanvasOptionsView: View {
    @Binding var settings: ExportCanvasSettings
    /// Emitted as `Section`s so both export sheets can put them in a
    /// grouped `Form` — the controls had grown to nine in one flat stack,
    /// where nothing said which of them changed the picture and which
    /// changed the file.
    var body: some View {
        Section("Appearance") {
            Picker("Include UI", selection: $settings.includeAppUI) {
                Text("Ring only").tag(false)
                Text("App screen").tag(true)
            }

            if settings.includeAppUI {
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
            .pickerStyle(.segmented)
        }

        // Only with the app screen: the frame wraps a screen, and there
        // isn't one to wrap around a bare ring.
        if settings.includeAppUI {
            Section("iPhone") {
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
