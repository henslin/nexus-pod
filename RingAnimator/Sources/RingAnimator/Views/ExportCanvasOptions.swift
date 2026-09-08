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
    var appearance: ColorScheme = .dark
    var transparent = false
    var includeAppUI = false
    var tab: DemoTab = .dashboard
    var includeDeviceFrame = false
    var finish: AnimationExporter.DeviceFinish = .silver

    var canvas: AnimationExporter.Canvas {
        guard includeAppUI else { return .ring }
        return .appUI(tab: tab, device: includeDeviceFrame ? finish : nil)
    }

    /// A bare phone screen is opaque edge to edge, so there's nothing for
    /// transparency to keep. Framed, there is: the rounded corners.
    var transparencyUnavailable: Bool {
        includeAppUI && !includeDeviceFrame
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
    /// The single export sheet offers transparency next to its own format
    /// toggles, where it reads as one list; the batch sheet has no such
    /// list and shows it here.
    var showsTransparency = true

    /// Emitted as `Section`s so both export sheets can put them in a
    /// grouped `Form` — the controls had grown to nine in one flat stack,
    /// where nothing said which of them changed the picture and which
    /// changed the file.
    var body: some View {
        Section("Appearance") {
            Picker("Theme", selection: $settings.appearance) {
                Text("Light").tag(ColorScheme.light)
                Text("Dark").tag(ColorScheme.dark)
            }
            .pickerStyle(.segmented)

            if showsTransparency {
                Toggle("Transparent background", isOn: $settings.transparent)
                    .disabled(settings.transparencyUnavailable)
                if settings.transparencyUnavailable {
                    Text("A full screen has no transparent edges to keep.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        Section("Frame it") {
            Toggle("Show the app around it", isOn: $settings.includeAppUI)
            if settings.includeAppUI {
                Picker("Tab", selection: $settings.tab) {
                    ForEach(DemoTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                Toggle("Show the iPhone", isOn: $settings.includeDeviceFrame)
                if settings.includeDeviceFrame {
                    Picker("Finish", selection: $settings.finish) {
                        ForEach(AnimationExporter.DeviceFinish.allCases) { finish in
                            Text(finish.rawValue).tag(finish)
                        }
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
        if settings.includeDeviceFrame {
            return "Exports the phone at \(dimensions). Turn on Transparent background to keep the rounded corners clear instead of filled."
        }
        return "Exports the phone screen at \(dimensions), square-cornered, ready to drop into a device frame. The screen is opaque, so there's no transparency to keep."
    }
}
