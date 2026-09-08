import Foundation
import RingAnimatorCore

// The Controls panel writes back into the selected timeline step. This
// checks it writes into the right one.
//
// It didn't. Pasting several use cases into a sequence and then touching
// anything produced a step that kept its own name and length while its
// contents became a different animation entirely — so the block read
// "Listen Rainbow Twin Pulse" and played Speaking Response Waveform. The
// data was wrong on disk, not just on screen, which is why this is a gate
// and not a note.
//
// `swift run TimelineCheck` — run by preflight.sh.

@MainActor
func run() -> Int32 {
    var failed = false
    func check(_ label: String, _ ok: Bool, _ detail: String) {
        print("  \(ok ? "✓" : "✗") \(label) — \(detail)")
        if !ok { failed = true }
    }

    let url = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Application Support/RingAnimator/use-cases.json")
    guard let data = try? Data(contentsOf: url),
          let library = try? JSONDecoder().decode([RingPreset].self, from: data),
          library.count >= 2 else {
        print("  ! skipped — no use case library to build a sequence from")
        return 0
    }
    // Two animations that differ in a way that's obvious in one field.
    guard let a = library.first(where: { $0.firmwarePatternStream != nil }),
          let b = library.first(where: { $0.firmwarePatternStream != nil && $0.id != a.id })
    else {
        print("  ! skipped — need two stream-backed animations")
        return 0
    }

    /// Long enough for the apply-suppression flag and the debounced
    /// capture to have run; both are next-runloop-turn, not timed.
    func settle() { RunLoop.current.run(until: Date().addingTimeInterval(0.3)) }

    func freshPlayer() -> (TimelinePlayer, RingConfig) {
        TimelinePlayer.deleteStore(fileName: "timeline-check.json")
        let player = TimelinePlayer(fileName: "timeline-check.json")
        player.installImported(RingTimeline())
        let live = RingConfig()
        player.bind(to: live)
        return (player, live)
    }

    // 1. Pasting keeps each animation's own contents.
    do {
        let (player, _) = freshPlayer()
        player.addSegment(from: a)
        player.addSegment(from: b)
        settle()
        let streams = player.timeline.segments.map { $0.snapshot.firmwarePatternStream ?? "none" }
        check("pasted steps hold what was pasted",
              streams == [a.firmwarePatternStream, b.firmwarePatternStream].map { $0 ?? "none" },
              streams.joined(separator: ", "))
    }

    // 2. Editing the selected step still writes into it. The guard below
    //    must not be so strict that ordinary editing stops working.
    do {
        let (player, live) = freshPlayer()
        player.addSegment(from: a)
        settle()
        live.speed = 2.5
        settle()
        check("editing the selected step is captured",
              player.timeline.segments.first?.snapshot.speed == 2.5,
              "speed \(player.timeline.segments.first?.snapshot.speed ?? -1)")
    }

    // 3. Loading a different animation into the ring must not overwrite
    //    the selected step with it. This is the bug, exactly.
    do {
        let (player, live) = freshPlayer()
        player.addSegment(from: a)
        player.addSegment(from: b)
        guard let stepA = player.timeline.segments.first else { return 1 }
        player.select(stepA.id)
        settle()

        // What `SavedPresetsView` does when you click a saved animation.
        b.apply(to: live)
        player.noteConfigReplaced()
        live.speed += 0.001                       // any edit at all
        settle()

        let stream = player.timeline.segments.first?.snapshot.firmwarePatternStream
        check("a step isn't overwritten by an animation loaded into the ring",
              stream == a.firmwarePatternStream,
              "step 1 holds \(stream ?? "none"), expected \(a.firmwarePatternStream ?? "none")")
    }

    // 4. And selecting a step again re-arms the write-back, so the guard
    //    is a pause rather than a permanent stop.
    do {
        let (player, live) = freshPlayer()
        player.addSegment(from: a)
        guard let stepA = player.timeline.segments.first else { return 1 }
        player.noteConfigReplaced()
        player.select(stepA.id)
        settle()
        live.speed = 3.75
        settle()
        check("selecting a step re-arms the write-back",
              player.timeline.segments.first?.snapshot.speed == 3.75,
              "speed \(player.timeline.segments.first?.snapshot.speed ?? -1)")
    }

    // 5. Each Nexus animation has its own sequence.
    //
    //    It used to have one shared document: selecting a different saved
    //    animation left the previous one's steps in the strip, and a new
    //    animation opened holding them.
    do {
        let first = UUID(), second = UUID()
        for id in [first, second] {
            TimelinePlayer.deleteStore(fileName: TimelinePlayer.animationFileName(id))
        }
        let one = TimelinePlayer(fileName: TimelinePlayer.animationFileName(first))
        one.bind(to: RingConfig())
        one.addSegment(from: a)
        settle()

        let two = TimelinePlayer(fileName: TimelinePlayer.animationFileName(second))
        check("a different animation starts with an empty sequence",
              two.timeline.segments.isEmpty,
              "\(two.timeline.segments.count) steps")

        two.bind(to: RingConfig())
        two.addSegment(from: b)
        settle()

        let reloaded = TimelinePlayer(fileName: TimelinePlayer.animationFileName(first))
        check("each animation keeps its own steps",
              reloaded.timeline.segments.count == 1
                  && reloaded.timeline.segments.first?.snapshot.firmwarePatternStream == a.firmwarePatternStream,
              "first animation holds \(reloaded.timeline.segments.map(\.name).joined(separator: ", "))")

        for id in [first, second] {
            TimelinePlayer.deleteStore(fileName: TimelinePlayer.animationFileName(id))
        }
    }

    // 6. What batch export asks before it renders: does this animation
    //    have a sequence? Getting `nil` here is what made exporting a
    //    multi-step animation quietly render its base settings instead.
    do {
        let id = UUID()
        let name = TimelinePlayer.animationFileName(id)
        TimelinePlayer.deleteStore(fileName: name)
        check("an animation with no sequence reports none",
              TimelinePlayer.storedTimeline(fileName: name) == nil, "nil")

        let player = TimelinePlayer(fileName: name)
        player.bind(to: RingConfig())
        player.addSegment(from: a)
        player.addSegment(from: b)
        settle()

        let found = TimelinePlayer.storedTimeline(fileName: name)
        check("an animation with steps hands them to the exporter",
              found?.segments.count == 2,
              "\(found?.segments.count ?? 0) steps, \(String(format: "%.1f", found?.duration ?? 0))s")
        TimelinePlayer.deleteStore(fileName: name)
    }

    // 7. Undo. A drag registers one step, not one per frame — otherwise
    //    ⌘Z rewinds a resize a pixel at a time.
    do {
        let (player, _) = freshPlayer()
        let undo = UndoManager()
        undo.groupsByEvent = false
        player.undoManager = undo

        player.addSegment(from: a)
        settle()
        check("adding a step can be undone", undo.canUndo, "canUndo \(undo.canUndo)")

        undo.undo()
        settle()
        check("undo takes the step back out", player.timeline.segments.isEmpty,
              "\(player.timeline.segments.count) steps")

        undo.redo()
        settle()
        check("redo puts it back", player.timeline.segments.count == 1,
              "\(player.timeline.segments.count) steps")

        // A drag: many updates between begin and end, one undo step.
        guard let step = player.timeline.segments.first else { return 1 }
        player.beginCoalescedEdit()
        for tenths in 1...12 {
            player.updateSegment(step.id) { $0.length = .seconds(Double(tenths) / 2) }
        }
        player.endCoalescedEdit(named: "Resize Step")
        settle()
        let resized = player.timeline.segments.first?.length.duration(speed: step.speed) ?? 0
        undo.undo()
        settle()
        let restored = player.timeline.segments.first?.length.duration(speed: step.speed) ?? 0
        check("a whole resize drag is one undo step",
              abs(resized - 6.0) < 0.001 && abs(restored - 6.0) > 0.001,
              String(format: "dragged to %.1fs, one undo returned it to %.1fs", resized, restored))
    }

    TimelinePlayer.deleteStore(fileName: "timeline-check.json")
    return failed ? 1 : 0
}

print("timeline write-back:")
exit(run())
