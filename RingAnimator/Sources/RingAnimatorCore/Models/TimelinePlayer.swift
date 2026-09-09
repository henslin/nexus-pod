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
        didSet {
            timelineRevision &+= 1
            scheduleSave()
        }
    }

    /// Bumped on every timeline mutation, including the write-back that
    /// captures a config edit into the selected step.
    ///
    /// `prepareForPlayback` used to re-apply only when the playhead crossed
    /// into a *different* segment, which was correct while the preview
    /// only rendered `playbackConfig` during playback — nobody edits mid-
    /// play. Once the paused preview started rendering it too, that guard
    /// meant no edit ever reached the picture: you'd drag a slider, the
    /// capture would land in the segment a runloop later, and
    /// `playbackConfig` would keep serving the snapshot it took when the
    /// playhead arrived. Every control looked dead.
    private var timelineRevision = 0
    private var lastAppliedRevision: Int?

    /// Which segment the Controls panel is currently editing. `nil` means
    /// "not editing any segment" — the live config is its own thing again,
    /// which is the state the app starts in.
    @Published public private(set) var selectedSegmentID: UUID?

    @Published public var isPlaying: Bool = false {
        didSet {
            guard isPlaying != oldValue else { return }
            if isPlaying {
                playAnchor = (date: Date(), offset: pausedPlayhead)
            } else if let anchor = playAnchor {
                // Freeze where it got to, so play resumes rather than
                // restarting.
                pausedPlayhead = anchor.offset + Date().timeIntervalSince(anchor.date)
                playAnchor = nil
            }
        }
    }

    /// Where the playhead sits while stopped, and the wall-clock instant
    /// playback started from it.
    ///
    /// Deliberately *not* `@Published`: the playhead moves every frame,
    /// and republishing it sixty times a second would redraw every view
    /// observing this object. Views ask `currentTime(at:)` with their own
    /// `TimelineView` date instead, which keeps playback a pure function
    /// of time — the same contract `TimelinePlayback` and
    /// `RingTimeline.resolve(at:)` already keep.
    ///
    /// Lives here rather than in a view because iOS has two places that
    /// need the same playhead at once: the ring pod on the main screen and
    /// the strip inside the settings sheet. The Mac app predates this and
    /// keeps its own anchor in `PreviewTab`; both work, and unifying them
    /// is tidying for its own sake rather than a fix.
    public private(set) var pausedPlayhead: Double = 0
    private var playAnchor: (date: Date, offset: Double)?

    /// Seconds into the timeline at a given wall-clock instant.
    public func currentTime(at date: Date) -> Double {
        guard let playAnchor else { return pausedPlayhead }
        return playAnchor.offset + date.timeIntervalSince(playAnchor.date)
    }

    /// Jump the playhead. Keeps running if it already was — scrubbing
    /// mid-playback should move and carry on, the way a video scrubber
    /// does.
    public func scrub(to time: Double) {
        let clamped = max(time, 0)
        pausedPlayhead = clamped
        if isPlaying {
            playAnchor = (date: Date(), offset: clamped)
        }
    }

    /// Resolved frame for a given instant, or nil when nothing should
    /// override the ring's own clock.
    /// The frame the playhead is parked on — **playing or not**.
    ///
    /// Gated on `isPlaying` until now, which meant the playhead and the
    /// picture parted company the moment you stopped: pausing snapped away
    /// from the frame you were watching, and scrubbing moved a value
    /// nothing followed. Nil only when there is no sequence to follow at
    /// all, which is the plain single-animation case.
    public func playback(at date: Date) -> TimelinePlayback? {
        guard let resolved = timeline.resolve(at: currentTime(at: date)) else { return nil }
        prepareForPlayback(resolved)
        return TimelinePlayback(resolved)
    }

    /// What a preview should render at that instant.
    ///
    /// Lives here rather than in each pane because it was written twice —
    /// once in `PreviewTab`, once in `UseCaseDetailView` — and the two
    /// drifted, so a fix to one left the other showing the wrong
    /// animation. One implementation, both callers.
    ///
    /// The snapshot trails `fallback` by a runloop while you drag a slider
    /// (`captureIntoSelectedSegment` writes it back on the next turn),
    /// which at 60fps is 16ms. Rendering `fallback` for the selected step
    /// instead would put that one step on its own free clock while every
    /// other step obeyed the playhead.
    public func displayConfig(for playback: TimelinePlayback?, fallback: RingConfig) -> RingConfig {
        playback == nil ? fallback : playbackConfig
    }

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

    /// Store file for a timeline belonging to one use case.
    ///
    /// A file per use case rather than one dictionary keyed by ID: it
    /// keeps `RingPreset` a flat snapshot, which matters more than it
    /// looks. `TimelineSegment.snapshot` *is* a `RingPreset`, so giving
    /// `RingPreset` a timeline of its own would let a step contain a
    /// timeline containing steps — recursion the type system would happily
    /// allow and nothing would stop.
    public static func useCaseFileName(_ id: UUID) -> String {
        "use-case-timeline-\(id.uuidString).json"
    }

    /// The same idea for a Nexus saved animation: its own sequence, in its
    /// own file, keyed by the animation's id.
    ///
    /// Nexus used to keep *one* timeline for the whole section — a saved
    /// animation was a bookmark of the live config alone, and the sequence
    /// was a separate shared document. That meant selecting a different
    /// animation left the previous animation's steps in the strip, and a
    /// brand-new animation opened with them too. Use cases never had that
    /// problem, having always been keyed this way.
    /// Reads a stored sequence without standing up a player.
    ///
    /// Exporting needs to know whether an animation *has* steps, for every
    /// animation in a batch. Constructing a `TimelinePlayer` each time
    /// would bring a playhead, a save debounce and a Combine binding along
    /// for a question answered by one file read.
    /// Posted after any sequence is written, carrying its `fileName`.
    public static let didChange = Notification.Name("com.nexusringapp.timelineDidChange")

    public static func storedTimeline(fileName: String) -> RingTimeline? {
        guard
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
            let data = try? Data(contentsOf: base
                .appendingPathComponent("RingAnimator", isDirectory: true)
                .appendingPathComponent(fileName)),
            let decoded = try? JSONDecoder().decode(RingTimeline.self, from: data),
            !decoded.isEmpty
        else { return nil }
        return decoded
    }

    public static func animationFileName(_ id: UUID) -> String {
        "animation-timeline-\(id.uuidString).json"
    }

    /// Deletes a timeline store. Called when its use case is deleted, so
    /// the file doesn't outlive what it belonged to.
    public static func deleteStore(fileName: String) {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        let url = base
            .appendingPathComponent("RingAnimator", isDirectory: true)
            .appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }

    public init(fileName: String = "timeline.json") {
        self.fileName = fileName
        self.timeline = RingTimeline()
        load()
    }

    // MARK: - Controls ⇄ selected segment

    /// Wires this player to the app's live `RingConfig`. Call once, from
    /// the view that owns both.
    /// Which segment the bound config was last loaded *from*.
    ///
    /// The capture below writes the live config into the selected step, and
    /// on its own that is only correct while the two agree. If the config
    /// is holding one animation and a different step is selected, the next
    /// edit silently overwrites that step with the other one's settings —
    /// keeping its name and length, so the block still reads correctly
    /// while its contents are somebody else's. That is not hypothetical:
    /// it is what pasting several use cases and then editing produced, and
    /// `TimelineCheck` reproduces it.
    private var configSourceSegmentID: UUID?

    // MARK: - Undo

    /// Set by the timeline strip from its environment. Weak: the window
    /// owns it, this doesn't.
    public weak var undoManager: UndoManager?

    /// The timeline as it was when a coalesced edit began — a resize or a
    /// reorder drag, which would otherwise register an undo step per
    /// frame and make ⌘Z a way to rewind a drag one pixel at a time.
    private var coalescedBaseline: RingTimeline?

    public func beginCoalescedEdit() {
        coalescedBaseline = timeline
    }

    public func endCoalescedEdit(named name: String) {
        defer { coalescedBaseline = nil }
        guard let baseline = coalescedBaseline, baseline != timeline else { return }
        registerUndo(name: name, restoring: baseline)
    }

    /// Runs a mutation and makes it undoable, unless a drag is already
    /// coalescing edits — in which case that drag registers the one step.
    private func undoable(_ name: String, _ mutate: () -> Void) {
        guard coalescedBaseline == nil else { return mutate() }
        let before = timeline
        mutate()
        guard before != timeline else { return }
        registerUndo(name: name, restoring: before)
    }

    /// Registers the inverse. Undoing runs this closure, which registers
    /// *its* inverse — which is what the undo manager then offers as redo.
    private func registerUndo(name: String, restoring snapshot: RingTimeline) {
        guard let undoManager else { return }
        // A manager that doesn't group by event throws on a bare
        // registration. SwiftUI's does group, but crashing is a poor way
        // to find out that something else doesn't.
        let needsGroup = !undoManager.groupsByEvent
        if needsGroup { undoManager.beginUndoGrouping() }
        defer { if needsGroup { undoManager.endUndoGrouping() } }
        undoManager.registerUndo(withTarget: self) { player in
            // The undo manager calls back on the thread that registered,
            // which is the main one — this states that rather than hopping
            // and landing a frame later.
            MainActor.assumeIsolated {
            let current = player.timeline
            player.timeline = snapshot
            // Keep a selection only if it still refers to something.
            if let id = player.selectedSegmentID,
               !snapshot.segments.contains(where: { $0.id == id }) {
                player.selectedSegmentID = snapshot.segments.first?.id
            }
            player.saveNow()
            player.registerUndo(name: name, restoring: current)
            }
        }
        undoManager.setActionName(name)
    }

    public func bind(to config: RingConfig) {
        boundConfig = config
        configSourceSegmentID = nil
        cancellables.removeAll()

        config.objectWillChange
            .sink { [weak self] _ in
                self?.scheduleCaptureIntoSelectedSegment()
            }
            .store(in: &cancellables)
    }

    /// Say that something has loaded a *different* animation into the
    /// bound config — loading a saved animation into the ring, say.
    ///
    /// Without this the next edit captures that animation into whichever
    /// step happens to be selected, overwriting it while leaving its name
    /// and length in place, so the block still reads correctly and its
    /// contents are somebody else's. There are two such callers, both in
    /// `SavedPresetsView`; anything new that replaces the live config
    /// wholesale belongs here too.
    public func noteConfigReplaced() {
        configSourceSegmentID = nil
        pendingCapture?.cancel()
        pendingCapture = nil
    }

    /// Loads a segment's snapshot into the bound config and marks it as the
    /// one the Controls panel is now editing.
    public func select(_ id: UUID?) {
        guard let id, let segment = timeline.segments.first(where: { $0.id == id }) else {
            selectedSegmentID = nil
            return
        }
        selectedSegmentID = id
        // A capture queued under the previous selection must not land now
        // that the selection has moved.
        pendingCapture?.cancel()
        pendingCapture = nil

        if let config = boundConfig {
            configSourceSegmentID = id
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
        // Only write back into the step this config was loaded from.
        // Anything else is one animation's settings landing on another
        // step — see `configSourceSegmentID`.
        guard configSourceSegmentID == id else { return }

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
        guard lastAppliedPlaybackSegmentID != resolved.segment.id
            || lastAppliedRevision != timelineRevision
        else { return }
        lastAppliedPlaybackSegmentID = resolved.segment.id
        lastAppliedRevision = timelineRevision
        let snapshot = resolved.segment.snapshot
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            snapshot.apply(to: self.playbackConfig)
            // The timeline owns fading now — see `TimelineSegment.opacity`.
            // Leaving the snapshot's own single-segment Playback envelope
            // switched on would multiply the two together and double-fade.
            self.playbackConfig.sequencePlaybackEnabled = false
            // Preview size is a property of the workspace, not of the
            // animation: it's the "Preview size" slider, and `RingPreset`
            // deliberately doesn't carry it. Without this line
            // `playbackConfig` keeps `RingConfig`'s default 160 while the
            // live config holds whatever the slider says, so the ring
            // visibly jumps size the moment the preview starts rendering
            // from a segment and jumps back when it stops.
            if let bound = self.boundConfig {
                self.playbackConfig.previewDiameter = bound.previewDiameter
            }
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
        undoable("Add Step") {
            timeline.segments.append(segment)
            select(segment.id)
            saveNow()
        }
        return segment
    }

    /// Appends a *saved* animation as a step — the path for building one
    /// sequence out of several use cases.
    ///
    /// Unlike `addSegment(from config:)` this keeps the animation's own
    /// name, because "Wifi Pairing" is what you want to see on the block
    /// rather than "Step 4", and takes its length from the animation
    /// rather than the 1.5s default: pasting a 17-second pairing sequence
    /// and getting a second and a half of it is not what anyone means.
    @discardableResult
    public func addSegment(from preset: RingPreset) -> TimelineSegment {
        let segment = TimelineSegment(
            name: preset.name,
            snapshot: preset,
            length: .seconds(Self.naturalLength(of: preset))
        )
        undoable("Paste Step") {
            timeline.segments.append(segment)
            select(segment.id)
            saveNow()
        }
        return segment
    }

    /// How long an animation runs before it repeats.
    ///
    /// A recorded stream knows exactly — that's its own recorded length.
    /// Everything else loops once per cycle at its own speed, clamped to
    /// the same 1...8 second range `AnimationExporter` uses when it picks
    /// an export length, for the same reason: a very slow animation would
    /// otherwise occupy the timeline for a minute.
    static func naturalLength(of preset: RingPreset) -> Double {
        if let name = preset.firmwarePatternStream,
           let stream = FirmwarePatternStream.stream(named: name) {
            return max(Double(stream.totalMs) / 1000, 0.1)
        }
        return min(max(1 / max(preset.speed, 0.05), 1), 8)
    }

    /// Replaces the whole timeline with one an importer built, and
    /// selects its first step.
    ///
    /// Saves immediately rather than through the debounce: this replaces a
    /// document wholesale, and the debounce exists for the opposite case —
    /// a slider being dragged, where the intermediate values aren't worth
    /// a write each. Losing this one to a quit two seconds later would
    /// lose the entire import.
    ///
    /// Selecting the first step is what makes the Controls panel show the
    /// imported pattern rather than whatever was being edited before, and
    /// `select` already loads that step's snapshot into the bound config.
    /// An empty timeline is a meaningful import result, not a no-op: it
    /// means the pattern is a single looping behavior. Clearing the steps
    /// is what stops the strip from still showing the *previous* import's
    /// phases while the ring renders the new pattern — the same
    /// two-files-blended-together confusion the config reset exists to
    /// prevent, one level up.
    public func installImported(_ imported: RingTimeline) {
        timeline = imported
        select(imported.segments.first?.id)
        saveNow()
    }

    public func deleteSegment(_ id: UUID) {
        guard let index = timeline.segments.firstIndex(where: { $0.id == id }) else { return }
        undoable("Delete Step") {
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
        // Not wrapped: a reorder arrives one index at a time from a live
        // drag, and the strip brackets the whole drag as one edit.
        let segment = timeline.segments.remove(at: from)
        timeline.segments.insert(segment, at: target)
        saveNow()
    }

    public func duplicateSegment(_ id: UUID) {
        guard let index = timeline.segments.firstIndex(where: { $0.id == id }) else { return }
        var copy = timeline.segments[index]
        copy.id = UUID()
        copy.name = "\(copy.name) copy"
        undoable("Duplicate Step") {
            timeline.segments.insert(copy, at: index + 1)
            select(copy.id)
            saveNow()
        }
    }

    /// In-place edit of one segment's timeline-level fields (length, fades,
    /// name) — the things the strip's own inspector owns, as opposed to the
    /// snapshot, which the Controls panel owns.
    public func updateSegment(_ id: UUID, _ mutate: (inout TimelineSegment) -> Void) {
        guard let index = timeline.segments.firstIndex(where: { $0.id == id }) else { return }
        undoable("Edit Step") {
            mutate(&timeline.segments[index])
        }
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
        defer {
            // Rows elsewhere draw an animation's *first step* when it has
            // one, and nothing else would tell them a step was just pasted.
            NotificationCenter.default.post(
                name: TimelinePlayer.didChange, object: nil, userInfo: ["fileName": fileName]
            )
        }
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
