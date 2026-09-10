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
    var ran = 0
    func check(_ label: String, _ ok: Bool, _ detail: String) {
        ran += 1
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

    // What the paused preview renders.
    //
    // The preview used to read the live config whenever playback was
    // stopped, which meant the playhead and the picture disagreed the
    // moment you stopped moving: pausing snapped away from the frame you
    // were watching, and scrubbing moved a playhead nothing followed.
    // These assert the two pieces `ContentView.displayConfig(for:)` now
    // depends on.
    do {
        let live = RingConfig()
        live.previewDiameter = 260
        let player = TimelinePlayer(fileName: "timeline-preview-check.json")
        player.bind(to: live)

        let first = RingConfig()
        first.primaryColor = .red
        let second = RingConfig()
        second.primaryColor = .green
        player.addSegment(from: first, named: "One")
        player.addSegment(from: second, named: "Two")

        // A playhead inside the second step has to resolve to the second
        // step — this is what the preview follows while paused.
        let firstLength = player.timeline.segments[0].length.duration(speed: first.speed)
        let resolved = player.timeline.resolve(at: firstLength + 0.1)
        check("the playhead resolves to the step it's over",
              resolved?.segment.name == "Two",
              resolved?.segment.name ?? "nothing")

        if let resolved {
            player.prepareForPlayback(resolved)
            // The apply is deferred one runloop on purpose (see
            // `prepareForPlayback`), so let it land.
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            check("preview size survives the switch to a segment",
                  player.playbackConfig.previewDiameter == 260,
                  "\(player.playbackConfig.previewDiameter) vs the workspace's 260")
        }
        TimelinePlayer.deleteStore(fileName: "timeline-preview-check.json")
    }

    // An edit has to reach the paused preview.
    //
    // The preview renders `playbackConfig` whenever a sequence is loaded,
    // stopped or not. `prepareForPlayback` used to re-apply only when the
    // playhead crossed into a different segment — fine while the config was
    // only read during playback, and fatal once it was read while editing:
    // every control in the app looked dead, because the picture was serving
    // the snapshot taken when the playhead arrived.
    do {
        let live = RingConfig()
        let player = TimelinePlayer(fileName: "timeline-live-edit-check.json")
        player.bind(to: live)

        let step = RingConfig()
        step.ringScale = 1
        player.addSegment(from: step, named: "Only")
        guard let id = player.timeline.segments.first?.id else {
            print("  ✗ no segment to edit")
            return 1
        }
        player.select(id)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        guard let resolved = player.timeline.resolve(at: 0.1) else {
            print("  ✗ nothing resolved at the playhead")
            return 1
        }
        player.prepareForPlayback(resolved)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let before = player.playbackConfig.ringScale

        // The edit, exactly as a slider drag makes it.
        live.ringScale = 0.5
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        if let again = player.timeline.resolve(at: 0.1) {
            player.prepareForPlayback(again)
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        }

        check("an edit reaches the paused preview",
              player.playbackConfig.ringScale == 0.5,
              "playbackConfig holds \(player.playbackConfig.ringScale), was \(before)")
        TimelinePlayer.deleteStore(fileName: "timeline-live-edit-check.json")
    }

    // Switching animations must stop the old one writing.
    //
    // Nexus keeps one player per saved animation, cached by id, and binds
    // the newly selected one to the live config. Nothing unbound the
    // previous one — its Combine subscription to that same config was
    // still live — so an edit made while looking at animation B could land
    // in animation A's selected step. Same shape as the write-back bug
    // above, one level up: not the wrong step, the wrong animation.
    do {
        let live = RingConfig()
        live.speed = 1

        let first = TimelinePlayer(fileName: "cross-animation-a.json")
        first.bind(to: live)
        first.addSegment(from: live, named: "A's step")
        if let id = first.timeline.segments.first?.id { first.select(id) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))

        // Now the user picks a different animation.
        // What `ContentView.TimelinePlayers.bind` does when the selection
        // moves: bind the new one, unbind the old one.
        let second = TimelinePlayer(fileName: "cross-animation-b.json")
        first.unbind()
        second.bind(to: live)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        // ...and turns a knob while looking at it.
        live.speed = 9
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))

        let landed = first.timeline.segments.first?.snapshot.speed ?? -1
        check("an edit can't land in the animation you left",
              abs(landed - 1) < 0.001,
              String(format: "A's step holds speed %.1f, expected 1.0", landed))

        TimelinePlayer.deleteStore(fileName: "cross-animation-a.json")
        TimelinePlayer.deleteStore(fileName: "cross-animation-b.json")
    }

    TimelinePlayer.deleteStore(fileName: "timeline-check.json")
    if ran != expectedAssertions {
        print("  ✗ ran \(ran) assertions, expected \(expectedAssertions) — "
              + (ran < expectedAssertions
                 ? "one skipped itself because its inputs came back nil"
                 : "update expectedAssertions"))
        failed = true
    }

    return failed ? 1 : 0
}

/// How many assertions this check is supposed to run.
///
/// Every one of these targets builds its own inputs — render a frame,
/// write a GIF, decode it back — and every one of those steps is an
/// optional that can come back nil. Where that happens inside an `if let`
/// or a `guard ... else { continue }`, the assertions underneath simply
/// don't run and the gate still reports green. That is not hypothetical:
/// `Pixels` rejected wide-gamut renders for a while, and two assertions
/// about Ring Size quietly did nothing.
///
/// Counting them closes the whole class at once, including the paths
/// nobody has thought of yet. Adding an assertion without bumping this
/// fails too, which is the right direction to fail in.
let expectedAssertions = 16

print("timeline write-back:")
exit(run())
