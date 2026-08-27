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

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            track
            if let segment = player.selectedSegment {
                Divider()
                inspector(for: segment)
            }
        }
        .padding(12)
        .background(.regularMaterial)
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

            Button {
                onScrub(0)
            } label: {
                Image(systemName: "backward.end.fill")
            }
            .disabled(player.timeline.isEmpty)
            .help("Back to start")

            Toggle(isOn: $player.timeline.loops) {
                Image(systemName: "repeat")
            }
            .toggleStyle(.button)
            .help("Loop the whole sequence")

            Text(timecode)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                player.addSegment(from: config)
            } label: {
                Label("Add Step", systemImage: "plus")
            }
            .help("Add the current ring settings as a new step")

            if let selected = player.selectedSegmentID {
                Button {
                    player.duplicateSegment(selected)
                } label: {
                    Image(systemName: "plus.square.on.square")
                }
                .help("Duplicate the selected step")

                Button(role: .destructive) {
                    player.deleteSegment(selected)
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete the selected step")
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
                        }
                    }
                    playheadIndicator(totalWidth: geo.size.width)
                }
                .contentShape(Rectangle())
                // Click or drag anywhere on the track to scrub. Converting
                // x back to seconds uses the *laid-out* widths rather than
                // a flat time-to-pixels ratio, since `minBlockWidth` above
                // means short steps take up more width than their duration
                // strictly earns — without this, clicking a padded-out
                // short block would jump the playhead somewhere else.
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            onScrub(time(atX: value.location.x, widths: widths))
                        }
                )
            }
            .frame(height: Self.trackHeight)
        }
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
            HStack(spacing: 4) {
                Circle()
                    .fill(Color(hex: segment.snapshot.primaryColorHex))
                    .frame(width: 8, height: 8)
                Text(segment.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            Text(lengthLabel(for: segment))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
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
