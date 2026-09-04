import SwiftUI

/// Preview or Code, for any section.
public enum DetailTab: String, CaseIterable, Identifiable, Sendable {
    case preview = "Preview"
    case code = "Code"

    public var id: String { rawValue }
}

/// The detail pane every section shares: the Preview/Code control centered
/// at the top, and the two panes below it.
///
/// The control used to be a `ToolbarItem(placement: .principal)`, which put
/// it in the window's title bar — a different place from the appearance
/// controls it sits directly above, and only Nexus had it at all. Exporting
/// code was therefore something you could only do to the ring in Nexus, so
/// importing a Blender animation into a use case, tuning it, and taking
/// SwiftUI out the other end meant copying settings back to Nexus by hand.
///
/// **Both panes stay mounted**, toggled by opacity rather than swapped by a
/// `switch`. A `switch` gives each branch its own identity, so SwiftUI
/// tears down whichever isn't showing — which threw away the stage's
/// pan/zoom every time, since `ZoomableCanvas` keeps that in an
/// `NSScrollView` with nothing for SwiftUI to restore.
public struct DetailPane<Preview: View, Code: View>: View {
    @Binding var tab: DetailTab
    let preview: () -> Preview
    let code: () -> Code

    public init(
        tab: Binding<DetailTab>,
        @ViewBuilder preview: @escaping () -> Preview,
        @ViewBuilder code: @escaping () -> Code
    ) {
        self._tab = tab
        self.preview = preview
        self.code = code
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $tab) {
                ForEach(DetailTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            .padding(.top, 12)
            .padding(.bottom, 10)
            // Centered in the pane, which puts it directly over the
            // appearance controls floating at the top of the stage below.
            .frame(maxWidth: .infinity)

            ZStack {
                preview()
                    .opacity(tab == .preview ? 1 : 0)
                    .allowsHitTesting(tab == .preview)
                    .accessibilityHidden(tab != .preview)
                code()
                    .opacity(tab == .code ? 1 : 0)
                    .allowsHitTesting(tab == .code)
                    .accessibilityHidden(tab != .code)
            }
        }
    }
}
