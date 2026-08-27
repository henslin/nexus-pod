import Combine
import Foundation

/// Owns the timeline being edited, the playhead, and — the load-bearing
/// part — the two-way link between the Controls panel and whichever
/// segment is currently selected.
///
/// The editing model is Keynote's, not a scratchpad's: the timeline is the
/// document, and the Controls panel is an inspector *into the selected
/// segment* rather than a separate staging area you explicitly commit
/// from. Selecting a segment loads its snapshot into the live
/// `RingConfig`; every subsequent knob turn writes straight back into that
/// segment. There's no "save" step and no way for what you see to drift
/// from what's stored.
///
/// With nothing selected (or an empty timeline) the app behaves exactly as
/// it always has — one live `RingConfig` looping forever, no timeline
/// involved. The whole feature is additive: a timeline you never touch
/// costs you nothing.
///
/// `@unchecked Sendable`: same reasoning as `VoiceConversationController`
/// (see its doc comment) — the deferred `DispatchQueue.main` callbacks
/// below capture `self` in `@Sendable` closures, which requires this type
/// to be `Sendable`. Every mutation stays on the main thread already: the
/// only callers are SwiftUI views, a Combine sink on the config's own
/// main-thread `objectWillChange`, and these `.main`-targeted deferrals.
public final class TimelinePlayer: ObservableObject, @unchecked Sendable {
    @Published public var timeline: RingTimeline {
        didSet { scheduleSave() }
    }

    /// Which segment the Controls panel is currently editing. `nil` means
    /// "not editing any segment" — the live config is its own thing again,
    /// which is the state the app starts in.
    @Published public private(set) var selectedSegmentID: UUID?

    @Published public var isPlaying: Bool = false
    /// Seconds into the timeline. Driven by the preview's own clock while
    /// playing, and by dragging the scrubber while not.
    @Published public var playhead: Double = 0

    /// The config the preview renders *while playing*, kept separate from
    /// the one Controls edits.
    ///
    /// Playing a timeline can't just drive the live config: that config is
    /// the selected segment (see the class doc comment), so writing each
    /// resolved snapshot into it would rewrite the document on every
    /// boundary the playhead crosses. A second config means playback is
    /// strictly read-only with respect to what you're editing.
    public let playbackConfig = RingConfig()

    /// Which segment `playbackConfig` currently holds — a plain stored
    /// property rather than `@Published` on purpose, since it's updated
    /// from inside a view body (see `prepareForPlayback`) where publishing
    /// would trigger SwiftUI's "modifying state during view update"
    /// warning.
    private var lastAppliedPlaybackSegmentID: UUID?

    private let fileName: String
    private var cancellables = Set<AnyCancellable>()
    private var boundConfig: RingConfig?

    /// Guards the write-back loop. `select(_:)` applies a snapshot *to* the
    /// config, which fires the config's own `objectWillChange`, which would
    /// otherwise immediately capture the config straight back into the
    /// segment — harmless in principle (it's the same data) but it fights
    /// with in-flight edits and makes every selection look like a mutation
    /// to the autosave. Set for the duration of an apply.
    private var isApplyingSnapshot = false

    /// Debounce token for the write-back. `objectWillChange` fires *before*
    /// the property actually changes, so capturing synchronously would
    /// snapshot the pre-edit value; deferring to the next runloop turn
    /// captures the settled state, and coalesces the burst of publishes a
    /// single slider drag produces into one write.
    private var pendingCapture: DispatchWorkItem?

    public init(fileName: String = "timeline.json") {
        self.fileName = fileName
        self.timeline = RingTimeline()
        load()
    }

    // MARK: - Controls ⇄ selected segment

    /// Wires this player to the app's live `RingConfig`. Call once, from
    /// the view that owns both.
    public func bind(to config: RingConfig) {
        boundConfig = config
        cancellables.removeAll()

        config.objectWillChange
            .sink { [weak self] _ in
                self?.scheduleCaptureIntoSelectedSegment()
            }
            .store(in: &cancellables)
    }

    /// Loads a segment's snapshot into the bound config and marks it as the
    /// one the Controls panel is now editing.
    public func select(_ id: UUID?) {
        guard let id, let segment = timeline.segments.first(where: { $0.id == id }) else {
            selectedSegmentID = nil
            return
        }
        selectedSegmentID = id

        if let config = boundConfig {
            isApplyingSnapshot = true
            segment.snapshot.apply(to: config)
            // Cleared on the next runloop turn, not synchronously: the
            // `objectWillChange` publishes triggered by `apply(to:)` above
            // are delivered before then, and this flag is what makes them
            // no-ops.
            DispatchQueue.main.async { [weak self] in
                self?.isApplyingSnapshot = false
            }
        }
    }

    private func scheduleCaptureIntoSelectedSegment() {
        guard !isApplyingSnapshot, selectedSegmentID != nil else { return }
        pendingCapture?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.captureIntoSelectedSegment()
        }
        pendingCapture = work
        DispatchQueue.main.async(execute: work)
    }

    private func captureIntoSelectedSegment() {
        guard
            let id = selectedSegmentID,
            let config = boundConfig,
            let index = timeline.segments.firstIndex(where: { $0.id == id })
        else { return }

        // Only the snapshot is replaced — the segment's own identity, name,
        // length and fades are timeline-level properties that the Controls
        // panel doesn't own and must survive a config edit.
        let existing = timeline.segments[index]
        timeline.segments[index].snapshot = RingPreset(
            id: existing.snapshot.id,
            name: existing.snapshot.name,
            createdAt: existing.snapshot.createdAt,
            config: config
        )
    }

    /// Points `playbackConfig` at the resolved segment's snapshot, if it
    /// isn't already there.
    ///
    /// Safe to call every frame — it does nothing unless the playhead has
    /// actually crossed into a different segment. The apply itself is
    /// deferred to the next runloop turn because callers invoke this from
    /// inside a view body, and `apply(to:)` publishes: doing it inline
    /// would mutate observable state mid-render. The cost is that a
    /// boundary crossing lands one frame late, which is ~16ms and not
    /// perceivable.
    public func prepareForPlayback(_ resolved: RingTimeline.Resolved) {
        guard lastAppliedPlaybackSegmentID != resolved.segment.id else { return }
        lastAppliedPlaybackSegmentID = resolved.segment.id
        let snapshot = resolved.segment.snapshot
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            snapshot.apply(to: self.playbackConfig)
            // The timeline owns fading now — see `TimelineSegment.opacity`.
            // Leaving the snapshot's own single-segment Playback envelope
            // switched on would multiply the two together and double-fade.
            self.playbackConfig.sequencePlaybackEnabled = false
        }
    }

    // MARK: - Editing

    /// Appends a new segment capturing the config's current state, and
    /// selects it. This is the "commit what I've been tuning" action.
    @discardableResult
    public func addSegment(from config: RingConfig, named name: String? = nil) -> TimelineSegment {
        let index = timeline.segments.count + 1
        let segmentName = name ?? "Step \(index)"
        let segment = TimelineSegment(
            name: segmentName,
            snapshot: RingPreset(name: segmentName, config: config),
            length: .seconds(1.5)
        )
        timeline.segments.append(segment)
        select(segment.id)
        saveNow()
        return segment
    }

    public func deleteSegment(_ id: UUID) {
        guard let index = timeline.segments.firstIndex(where: { $0.id == id }) else { return }
        timeline.segments.remove(at: index)
        if selectedSegmentID == id {
            // Select the neighbor that slid into the removed slot, or the
            // new last one if we deleted off the end — same behavior as
            // deleting a row in a list, rather than dropping selection
            // entirely and leaving the Controls panel pointing at nothing.
            let next = min(index, timeline.segments.count - 1)
            select(timeline.segments.indices.contains(next) ? timeline.segments[next].id : nil)
        }
        saveNow()
    }

    /// Moves one step to an absolute position in the list.
    ///
    /// Index-based rather than SwiftUI's `move(fromOffsets:toOffset:)`
    /// because the strip reorders *during* a drag, by asking "which slot
    /// is the pointer over right now" — and `toOffset`'s
    /// before-removal-adjustment semantics are a persistent off-by-one
    /// trap when the answer is already an absolute index. Remove-then-
    /// insert says exactly what it does.
    public func moveSegment(_ id: UUID, toIndex target: Int) {
        guard
            let from = timeline.segments.firstIndex(where: { $0.id == id }),
            timeline.segments.indices.contains(target),
            from != target
        else { return }
        let segment = timeline.segments.remove(at: from)
        timeline.segments.insert(segment, at: target)
        saveNow()
    }

    public func duplicateSegment(_ id: UUID) {
        guard let index = timeline.segments.firstIndex(where: { $0.id == id }) else { return }
        var copy = timeline.segments[index]
        copy.id = UUID()
        copy.name = "\(copy.name) copy"
        timeline.segments.insert(copy, at: index + 1)
        select(copy.id)
        saveNow()
    }

    /// In-place edit of one segment's timeline-level fields (length, fades,
    /// name) — the things the strip's own inspector owns, as opposed to the
    /// snapshot, which the Controls panel owns.
    public func updateSegment(_ id: UUID, _ mutate: (inout TimelineSegment) -> Void) {
        guard let index = timeline.segments.firstIndex(where: { $0.id == id }) else { return }
        mutate(&timeline.segments[index])
    }

    public var selectedSegment: TimelineSegment? {
        guard let id = selectedSegmentID else { return nil }
        return timeline.segments.first { $0.id == id }
    }

    // MARK: - Persistence
    //
    // Same Application Support JSON convention as `RingPresetStore` and
    // `LEDCueStore` — see `RingPresetStore`'s doc comment. Debounced rather
    // than written on every mutation, since dragging a fade slider mutates
    // the timeline continuously.

    private var pendingSave: DispatchWorkItem?

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Writes immediately, cancelling any debounced write already queued.
    ///
    /// The debounce exists for continuous edits — dragging a fade slider
    /// mutates the timeline on every frame — but it opens a window where
    /// quitting loses the last change. That's fine for "the fade is now
    /// 0.4 instead of 0.3" and not fine for "this step exists", so the
    /// structural edits below flush instead of waiting. Discrete actions
    /// are rare enough that writing on each one costs nothing.
    private func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        save()
    }

    private var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = base.appendingPathComponent("RingAnimator", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(fileName)
    }

    private func save() {
        guard let url = fileURL else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(timeline) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func load() {
        guard
            let url = fileURL,
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(RingTimeline.self, from: data)
        else { return }
        timeline = decoded
    }
}
