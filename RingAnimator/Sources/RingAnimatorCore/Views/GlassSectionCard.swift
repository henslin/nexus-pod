import SwiftUI

/// One collapsible card — the Liquid Glass equivalent of a `Form` grouped
/// `Section`, but as its own standalone floating shape instead of a row in
/// one continuous list background. Falls back to `.regularMaterial` on
/// pre-26 systems, the same `#available` pattern as `ContentView.glassRing`
/// and `ExportView`'s toolbar buttons.
///
/// `public` — unlike most of this package's views — specifically so both
/// Nexus's Controls panel (`ControlsView`, in this module) and the Cue
/// Library's per-cue editor (`CueExplorerView`, in the main `RingAnimator`
/// target) can build on the exact same card instead of one drifting into
/// its own look. Same cross-module reasoning as `ringGlassButtonStyle()`
/// in `ControlsSections.swift`.
public struct GlassSectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    var footer: String? = nil
    var masterToggle: Binding<Bool>? = nil
    @Binding var isExpanded: Bool
    @ViewBuilder var content: () -> Content

    public init(
        title: String,
        systemImage: String,
        footer: String? = nil,
        masterToggle: Binding<Bool>? = nil,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.footer = footer
        self.masterToggle = masterToggle
        self._isExpanded = isExpanded
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: systemImage)
                            .foregroundStyle(.secondary)
                        Text(title)
                            .font(.headline)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)

                if let masterToggle {
                    Toggle("", isOn: masterToggle)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        #if os(macOS)
                        .controlSize(.small)
                        #endif
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    content()
                    if let footer {
                        Text(footer)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                // Switches, not checkboxes.
                //
                // `toggleStyle` propagates through the environment, so
                // this one line covers every `Toggle` in every section
                // rather than fourteen call sites in
                // `ControlsSections.swift` — which is also why those call
                // sites stay style-free and keep working unchanged inside
                // iOS's `Form`.
                //
                // They were checkboxes because macOS's *default* toggle
                // style outside a `Form` is a checkbox, and `ControlsView`
                // deliberately left `Form` behind for these glass cards
                // (see its doc comment). Losing switch-styled toggles was
                // an unnoticed side effect of that move — the card header's
                // own master toggle sets `.switch` explicitly, which is why
                // a section could show a switch in its header and
                // checkboxes directly beneath it.
                .toggleStyle(.switch)
                #if os(macOS)
                .controlSize(.small)
                #endif
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        // Without this, the collapse/expand transition's opacity+move
        // animates the content sliding and fading past the card's own
        // edges instead of being masked by them — the rounded-rect glass
        // background sits behind an unclipped VStack, so a section with
        // tall content briefly overflows the card's shape mid-animation.
        // Clipping to the same shape `cardBackground()` draws keeps every
        // frame of the collapse contained to the card, not just the
        // settled start/end states.
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .cardBackground()
    }
}

private extension View {
    @ViewBuilder
    func cardBackground() -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}
