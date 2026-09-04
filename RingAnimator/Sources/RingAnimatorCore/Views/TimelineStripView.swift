import SwiftUI

/// The sequencing strip that sits under the canvas — segment blocks laid
/// out left to right, scaled by how long each one lasts, with a playhead
/// and a small inspector for the selected block.
///
/// Deliberately *not* the Controls panel in miniature. A block owns only
/// its timeline-level properties (name, length, fades); everything about
/// what the ring actually looks like stays in Controls, which edits the
/// selected block's snapshot directly (see `TimelinePlayer`'s doc comment
/// for the Keynote-style editing model this is the document half of).
/// Splitting it that way is what keeps "there is exactly one place to
/// change a knob" true after adding a second editing surface.
///
/// Lives in `RingAnimatorCore` rather than the Mac target — same reasoning
/// as `TabBarPreview`/`RingSettingsMenu` — so iOS can host the same strip
/// later without a second implementation to keep in sync.
public struct TimelineStripView: View {
    @ObservedObject var player: TimelinePlayer
    /// The live config the Controls panel edits. Needed for "Add Step",
    /// which snapshots whatever's currently tuned.
    @ObservedObject var config: RingConfig

    /// Current playhead position in seconds. Owned by whoever runs the
    /// clock (the preview, which needs it every frame anyway) and passed
    /// down as a value, so playback doesn't push a published change
    /// through this object sixty times a second.
    var playhead: Double
    var onScrub: (Double) -> Void

    public init(
        player: TimelinePlayer,
        config: RingConfig,
        playhead: Double,
        onScrub: @escaping (Double) -> Void
    ) {
        self.player = player
        self.config = config
        self.playhead = playhead
        self.onScrub = onScrub
    }

    /// Minimum on-screen width for a block, so a 0.1s step stays clickable
    /// instead of collapsing to a hairline.
    private static let minBlockWidth: CGFloat = 44
    private static let trackHeight: CGFloat = 56
    /// The inspector row's height, reserved whether or not a step is
    /// selected. Without this the strip grows the moment you select
    /// something and shrinks when you deselect, which moves every control
    /// above it — including the Add Step button, so a second click meant
    /// for it lands on the track instead. A strip that changes height
    /// under the pointer is worse than one with a little empty space in
    /// it.
    private static let inspectorHeight: CGFloat = 26
    /// Height of the scrub ruler above the blocks.
    private static let rulerHeight: CGFloat = 12
    /// Name for the track's coordinate space, so a block's own drag can
    /// report its pointer position in *track* coordinates rather than its
    /// own. That's what lets "which slot am I over" stay a simple lookup
    /// even as the blocks reorder underneath the pointer mid-drag.
    private static let trackSpace = "timeline.track"

    /// The step currently being dragged, if any. Only drives the lifted
    /// appearance — the actual reordering happens live in the drag handler,
    /// so there's no pending-move state to commit or roll back.
    @State private var draggingID: UUID?

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// True on a phone. The strip was designed for the Mac's
    /// canvas-bottom slot and its rows are simply wider than 402pt: on an
    /// iPhone the timecode was clipped mid-digit, "Add Step" collapsed to
    /// a bare "+", and the whole inspector row ran off both edges. Rather
    /// than shrink everything, the two rows that overflow rearrange.
    private var isCompact: Bool { horizontalSizeClass == .compact }
    #else
    private var isCompact: Bool { false }
    #endif

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            VStack(spacing: 4) {
                scrubRuler
                track
            }
            // On a phone the timecode moves out of the transport row,
            // which is where it ran out of width, and sits under the
            // track instead.
            if isCompact {
                Text(timecode)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Divider()
            // The inspector is a row of five controls and doesn't fit a
            // phone at any sensible size, so it scrolls there. Left
            // un-scrolled on the Mac, where it always fit and a scroll
            // view would only add a stray gutter.
            if isCompact {
                ScrollView(.horizontal, showsIndicators: false) {
                    inspectorRow
                        .frame(height: Self.inspectorHeight, alignment: .leading)
                        .padding(.trailing, 4)
                }
                .frame(height: Self.inspectorHeight)
            } else {
                inspectorRow
                    .frame(height: Self.inspectorHeight, alignment: .leading)
            }
        }
        .padding(12)
        // Real Liquid Glass where the OS has it, `.regularMaterial`
        // below — the strip is standalone chrome sitting on the canvas,
        // which by this codebase's convention is exactly the case that
        // needs the explicit treatment (buttons inside a List/Form/toolbar
        // get System-applied glass for free; see `ringGlassButtonStyle`).
        .glassBackground(in: Rectangle())
    }

    // MARK: - Transport

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                player.isPlaying.toggle()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 22)
            }
            .disabled(player.timeline.isEmpty)
            .help(player.isPlaying ? "Pause" : "Play the sequence")
            .ringGlassButtonStyle()

            Button {
                onScrub(0)
            } label: {
                Image(systemName: "backward.end.fill")
            }
            .disabled(player.timeline.isEmpty)
            .help("Back to start")
            .ringGlassButtonStyle()

            Toggle(isOn: $player.timeline.loops) {
                Image(systemName: "repeat")
            }
            .toggleStyle(.button)
            .ringGlassButtonStyle()
            .help("Loop the whole sequence")

            if !isCompact {
                Text(timecode)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                player.addSegment(from: config)
            } label: {
                Label("Add Step", systemImage: "plus")
            }
            .help("Add the current ring settings as a new step")
            .ringGlassButtonStyle()

            if let selected = player.selectedSegmentID {
                Button {
                    player.duplicateSegment(selected)
                } label: {
                    Image(systemName: "plus.square.on.square")
                }
                .help("Duplicate the selected step")
                .ringGlassButtonStyle()

                Button(role: .destructive) {
                    player.deleteSegment(selected)
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete the selected step")
                .ringGlassButtonStyle()
            }
        }
    }

    /// Where the playhead actually sits *within* the timeline. `playhead`
    /// itself is a free-running clock, so everything on screen has to go
    /// through the timeline's own mapping — see `normalizedTime`.
    private var position: Double {
        player.timeline.normalizedTime(playhead)
    }

    private var timecode: String {
        String(format: "%.2fs / %.2fs", position, player.timeline.duration)
    }

    // MARK: - Track

    /// Scrubbing lives here rather than on the blocks below, because the
    /// blocks now own a drag of their own for reordering and the two would
    /// otherwise compete for the same pointer movement. Splitting them is
    /// also just how a timeline usually works: you scrub the ruler and you
    /// drag the clips.
    ///
    /// Converting x back to seconds uses the *laid-out* widths rather than
    /// a flat time-to-pixels ratio, since `minBlockWidth` means short steps
    /// take up more width than their duration strictly earns — without
    /// that, clicking above a padded-out short block would jump the
    /// playhead somewhere else.
    @ViewBuilder
    private var scrubRuler: some View {
        if player.timeline.isEmpty {
            Color.clear.frame(height: Self.rulerHeight)
        } else {
            GeometryReader { geo in
                let widths = blockWidths(in: geo.size.width)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary.opacity(0.6))
                        .frame(height: 4)
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: Self.rulerHeight, height: Self.rulerHeight)
                        // Clamped to the track's own bounds. Centering the
                        // knob on the playhead puts half of it past the
                        // left edge at 0:00 (and past the right edge at the
                        // end), where the strip's padding clips it — it read
                        // as a half-circle stuck to the edge. Clamping only
                        // affects the two extremes; everything in between
                        // is unchanged.
                        .offset(x: min(
                            max(x(forTime: position, widths: widths) - Self.rulerHeight / 2, 0),
                            max(geo.size.width - Self.rulerHeight, 0)
                        ))
                }
                .frame(height: Self.rulerHeight)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            onScrub(time(atX: value.location.x, widths: widths))
                        }
                )
            }
            .frame(height: Self.rulerHeight)
        }
    }

    @ViewBuilder
    private var track: some View {
        if player.timeline.isEmpty {
            emptyTrack
        } else {
            GeometryReader { geo in
                let widths = blockWidths(in: geo.size.width)
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 4) {
                        ForEach(Array(player.timeline.segments.enumerated()), id: \.element.id) { index, segment in
                            block(segment, width: widths[index])
                                .gesture(reorderGesture(for: segment, widths: widths))
                        }
                    }
                    .animation(.spring(response: 0.28, dampingFraction: 0.82), value: player.timeline.segments.map(\.id))
                    playheadIndicator(totalWidth: geo.size.width)
                }
                .coordinateSpace(name: Self.trackSpace)
            }
            .frame(height: Self.trackHeight)
        }
    }

    /// Drag a block sideways to reorder. The list is rearranged *during*
    /// the drag rather than on release, so the gap opens where the step
    /// will land instead of everything jumping at the end.
    ///
    /// Reading the pointer in the track's coordinate space (not the
    /// block's own) is what makes that stable: once a move happens the
    /// dragged block sits under the pointer again, so the next lookup
    /// returns the same slot rather than oscillating between two.
    ///
    /// `minimumDistance: 4` leaves click-to-select to the block's own tap
    /// gesture — a plain click never travels far enough to start this.
    private func reorderGesture(for segment: TimelineSegment, widths: [CGFloat]) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.trackSpace))
            .onChanged { value in
                if draggingID != segment.id {
                    draggingID = segment.id
                    // Dragging a step also selects it, so the Controls
                    // panel follows what you're manipulating — same
                    // expectation as clicking it.
                    if player.selectedSegmentID != segment.id {
                        player.select(segment.id)
                    }
                }
                guard let target = index(atX: value.location.x, widths: widths) else { return }
                player.moveSegment(segment.id, toIndex: target)
            }
            .onEnded { _ in
                draggingID = nil
            }
    }

    /// Which block slot a track-space x lands in.
    private func index(atX x: CGFloat, widths: [CGFloat]) -> Int? {
        guard !widths.isEmpty else { return nil }
        var cursor: CGFloat = 0
        for (index, width) in widths.enumerated() {
            let end = cursor + width + 4
            if x < end { return index }
            cursor = end
        }
        return widths.count - 1
    }

    private var emptyTrack: some View {
        HStack {
            Spacer()
            VStack(spacing: 4) {
                Text("No steps yet")
                    .font(.callout.weight(.medium))
                Text("Tune the ring in Controls, then press Add Step.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(height: Self.trackHeight)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Widths proportional to duration, but never below `minBlockWidth`.
    /// The short blocks take their extra width out of the remaining space
    /// rather than overflowing the track.
    private func blockWidths(in totalWidth: CGFloat) -> [CGFloat] {
        let segments = player.timeline.segments
        guard !segments.isEmpty else { return [] }

        let spacing = CGFloat(max(segments.count - 1, 0)) * 4
        let available = max(totalWidth - spacing, Self.minBlockWidth)
        let total = player.timeline.duration

        guard total > 0 else {
            return Array(repeating: available / CGFloat(segments.count), count: segments.count)
        }

        // First pass: proportional. Second pass: lift anything under the
        // minimum and rescale the rest to absorb the difference.
        var widths = segments.map { max(available * CGFloat($0.duration / total), 0) }
        let shortIndices = widths.indices.filter { widths[$0] < Self.minBlockWidth }
        guard !shortIndices.isEmpty else { return widths }

        let reserved = CGFloat(shortIndices.count) * Self.minBlockWidth
        let remaining = max(available - reserved, 0)
        let flexibleTotal = widths.indices
            .filter { !shortIndices.contains($0) }
            .reduce(CGFloat(0)) { $0 + widths[$1] }

        for i in widths.indices {
            if shortIndices.contains(i) {
                widths[i] = Self.minBlockWidth
            } else if flexibleTotal > 0 {
                widths[i] = remaining * (widths[i] / flexibleTotal)
            }
        }
        return widths
    }

    private func time(atX x: CGFloat, widths: [CGFloat]) -> Double {
        let segments = player.timeline.segments
        var cursor: CGFloat = 0
        var elapsed: Double = 0
        for (index, width) in widths.enumerated() {
            let blockEnd = cursor + width
            if x <= blockEnd || index == widths.count - 1 {
                let fraction = width > 0 ? Double((x - cursor) / width) : 0
                return elapsed + min(max(fraction, 0), 1) * segments[index].duration
            }
            cursor = blockEnd + 4
            elapsed += segments[index].duration
        }
        return 0
    }

    private func block(_ segment: TimelineSegment, width: CGFloat) -> some View {
        let isSelected = player.selectedSegmentID == segment.id
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                StepPreview(snapshot: segment.snapshot)
                VStack(alignment: .leading, spacing: 1) {
                    Text(segment.name)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Text(lengthLabel(for: segment))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(width: width, height: Self.trackHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.28) : Color.secondary.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
        )
        // Lifted while dragging. Deliberately a scale/shadow rather than
        // following the pointer with an offset: the block is already being
        // reordered live, so it's under the pointer anyway, and an offset
        // on top of that reads as the block lagging its own drop target.
        .scaleEffect(draggingID == segment.id ? 1.04 : 1)
        .shadow(color: .black.opacity(draggingID == segment.id ? 0.35 : 0), radius: 8, y: 2)
        .zIndex(draggingID == segment.id ? 1 : 0)
        .animation(.easeOut(duration: 0.15), value: draggingID)
        // A plain tap gesture rather than a `Button`: the track's own scrub
        // drag gesture sits underneath, and a Button's tap handling fights
        // with it the same way it did in `PreviewTab`'s draggable preview
        // card (see the `.simultaneousGesture` comment there).
        .onTapGesture {
            player.select(segment.id)
        }
    }

    private func lengthLabel(for segment: TimelineSegment) -> String {
        switch segment.length {
        case .seconds:
            return String(format: "%.2fs", segment.duration)
        case .rotations(let r):
            return String(format: "%.2g× · %.2fs", r, segment.duration)
        }
    }

    @ViewBuilder
    private func playheadIndicator(totalWidth: CGFloat) -> some View {
        let total = player.timeline.duration
        if total > 0 {
            let widths = blockWidths(in: totalWidth)
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 2, height: Self.trackHeight)
                .offset(x: x(forTime: position, widths: widths))
                .allowsHitTesting(false)
        }
    }

    /// Inverse of `time(atX:widths:)` — same laid-out-width basis, so the
    /// indicator lands where a click at that time would.
    private func x(forTime t: Double, widths: [CGFloat]) -> CGFloat {
        let segments = player.timeline.segments
        var cursor: CGFloat = 0
        var elapsed: Double = 0
        for (index, width) in widths.enumerated() {
            let duration = segments[index].duration
            if t <= elapsed + duration || index == widths.count - 1 {
                let fraction = duration > 0 ? CGFloat((t - elapsed) / duration) : 0
                return cursor + min(max(fraction, 0), 1) * width
            }
            cursor += width + 4
            elapsed += duration
        }
        return cursor
    }

    // MARK: - Selected step inspector

    /// Always occupies `inspectorHeight` — see that constant. Falls back to
    /// a hint when there are steps but none is selected, and to nothing at
    /// all when the timeline is empty (the track's own empty state already
    /// says what to do, and repeating it here would just be noise).
    @ViewBuilder
    private var inspectorRow: some View {
        if let segment = player.selectedSegment {
            inspector(for: segment)
        } else if !player.timeline.isEmpty {
            Text("Select a step to edit its timing.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func inspector(for segment: TimelineSegment) -> some View {
        let id = segment.id
        HStack(alignment: .center, spacing: 14) {
            TextField("Name", text: Binding(
                get: { segment.name },
                set: { newValue in player.updateSegment(id) { $0.name = newValue } }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 130)

            Picker("", selection: Binding(
                get: { segment.length.isRotations },
                set: { useRotations in
                    player.updateSegment(id) { seg in
                        // Convert rather than reset, so flipping the unit
                        // keeps the step the same length instead of
                        // snapping it to a default.
                        seg.length = useRotations
                            ? .rotations(seg.length.rotations(speed: seg.speed))
                            : .seconds(seg.length.duration(speed: seg.speed))
                    }
                }
            )) {
                Text("Seconds").tag(false)
                Text("Rotations").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)

            lengthField(for: segment)

            Stepper(
                value: Binding(
                    get: { segment.fadeIn },
                    set: { newValue in player.updateSegment(id) { $0.fadeIn = max(newValue, 0) } }
                ),
                in: 0...10,
                step: 0.1
            ) {
                Text(String(format: "Fade In %.1fs", segment.fadeIn))
                    .font(.caption)
                    .monospacedDigit()
            }

            Stepper(
                value: Binding(
                    get: { segment.fadeOut },
                    set: { newValue in player.updateSegment(id) { $0.fadeOut = max(newValue, 0) } }
                ),
                in: 0...10,
                step: 0.1
            ) {
                Text(String(format: "Fade Out %.1fs", segment.fadeOut))
                    .font(.caption)
                    .monospacedDigit()
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func lengthField(for segment: TimelineSegment) -> some View {
        let id = segment.id
        switch segment.length {
        case .seconds(let value):
            Stepper(
                value: Binding(
                    get: { value },
                    set: { newValue in player.updateSegment(id) { $0.length = .seconds(max(newValue, 0)) } }
                ),
                in: 0.1...60,
                step: 0.1
            ) {
                Text(String(format: "Length %.1fs", value))
                    .font(.caption)
                    .monospacedDigit()
            }
        case .rotations(let value):
            Stepper(
                value: Binding(
                    get: { value },
                    set: { newValue in player.updateSegment(id) { $0.length = .rotations(max(newValue, 0)) } }
                ),
                in: 0.25...100,
                step: 0.25
            ) {
                Text(String(format: "Rotations %.2g", value))
                    .font(.caption)
                    .monospacedDigit()
            }
        }
    }
}

private extension SegmentLength {
    var isRotations: Bool {
        if case .rotations = self { return true }
        return false
    }
}


/// A live thumbnail of what a step actually looks like, in place of the
/// flat color dot the blocks used to carry.
///
/// Same shape as the rows in Saved Animations and Use Cases: a private
/// `RingConfig` the snapshot is applied into, rather than making the
/// caller assemble one or duplicating `RingPreset.apply(to:)`'s
/// field-by-field copy. The `onChange` keeps it current while you tune
/// the step, since the Controls panel edits the selected step's snapshot
/// live.
///
/// Deliberately smaller than those rows' 22pt ring: a block can be as
/// narrow as `minBlockWidth`, and at that size a 22pt ring leaves no room
/// for the name beside it.
private struct StepPreview: View {
    let snapshot: RingPreset

    @StateObject private var previewConfig = RingConfig()

    var body: some View {
        RingView(config: previewConfig, diameter: 15, frameRate: RingView.thumbnailFrameRate)
            .frame(width: 19, height: 19)
            .onAppear { snapshot.apply(to: previewConfig) }
            .onChange(of: snapshot) { _, newValue in newValue.apply(to: previewConfig) }
    }
}
