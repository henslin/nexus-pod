import SwiftUI

/// A row's little animating ring, showing what the animation actually is.
///
/// An animation with a sequence *is* that sequence — so the row draws its
/// first step rather than the base settings underneath it. Pasting a step
/// into an animation used to leave its row showing the old picture, which
/// read as "the paste didn't work" when the paste had worked fine.
///
/// The lookup is a file read, so it happens when the row appears, when its
/// animation changes, and when something writes that sequence — not on
/// every redraw, which for a column of eighty animating rows would be a
/// file read per row per frame.
public struct AnimationThumbnail: View {
    let preset: RingPreset
    let diameter: CGFloat
    /// Where this animation's sequence lives, if its section keeps them.
    let timelineFileName: String?

    @StateObject private var previewConfig = RingConfig()
    @State private var shown: RingPreset?

    public init(preset: RingPreset, diameter: CGFloat, timelineFileName: String?) {
        self.preset = preset
        self.diameter = diameter
        self.timelineFileName = timelineFileName
    }

    public var body: some View {
        RingView(config: previewConfig, diameter: diameter, frameRate: RingView.thumbnailFrameRate)
            .frame(width: diameter + 6, height: diameter + 6)
            .onAppear(perform: refresh)
            .onChange(of: preset) { _, _ in refresh() }
            .onReceive(NotificationCenter.default.publisher(for: TimelinePlayer.didChange)) { note in
                guard let name = note.userInfo?["fileName"] as? String,
                      name == timelineFileName else { return }
                refresh()
            }
    }

    private func refresh() {
        let first = timelineFileName
            .flatMap { TimelinePlayer.storedTimeline(fileName: $0) }?
            .segments.first?.snapshot
        let next = first ?? preset
        guard next != shown else { return }
        shown = next
        next.apply(to: previewConfig)
    }
}
