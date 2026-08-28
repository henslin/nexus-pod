import Foundation

/// How a segment's length is authored. The two cases are the same quantity
/// seen from either side of `rotations = seconds × speed` — the point of
/// keeping them as a choice (rather than storing both numbers) is that
/// only one can be the source of truth, and storing both lets them drift
/// the moment `speed` changes underneath them.
///
/// Which one you want depends on the intent:
/// - `.rotations` for "spin exactly three times" — the count is what
///   matters and the clock follows from it, so re-tuning `speed` changes
///   how long the segment takes without ever breaking the count.
/// - `.seconds` for "hold this for two beats" — the clock is what matters
///   and the rotation count follows, which is what you want for a segment
///   that isn't really spinning (a solid hold, a fade) where "rotations"
///   is a meaningless way to describe it.
public enum SegmentLength: Codable, Equatable, Hashable, Sendable {
    case seconds(Double)
    case rotations(Double)

    /// How long this segment occupies the timeline, in seconds.
    ///
    /// `speed` is cycles-per-second from the segment's own snapshot — see
    /// `RingConfig.speed`. Guarded against zero (and against a negative
    /// speed, which `RingView` tolerates as "spin backwards" but which
    /// would otherwise produce a negative duration here and silently
    /// corrupt every downstream offset).
    public func duration(speed: Double) -> Double {
        switch self {
        case .seconds(let s):
            return max(s, 0)
        case .rotations(let r):
            return max(r, 0) / max(abs(speed), 0.001)
        }
    }

    /// How many full rotations the ring turns through over this segment.
    /// The inverse of `duration(speed:)`, and what `RingTimeline`'s phase
    /// accumulator sums to keep rotation continuous across a boundary.
    public func rotations(speed: Double) -> Double {
        switch self {
        case .seconds(let s):
            return max(s, 0) * abs(speed)
        case .rotations(let r):
            return max(r, 0)
        }
    }
}

/// One step in a sequenced animation: a full snapshot of what the ring
/// looks like, plus how long it lasts and how it enters and leaves.
///
/// The snapshot is a `RingPreset` rather than a bespoke struct on purpose —
/// it's already the codebase's answer to "freeze a `RingConfig` into
/// something `Codable`", already excludes the things that aren't part of
/// the animation (preview sizing, background staging, live voice
/// credentials — see its own doc comment), and already knows how to
/// `apply(to:)` a config to play back. A segment being "a preset with
/// timing attached" also means anything you can save to Saved Animations
/// can become a timeline step and vice versa.
///
/// Deliberately a *full* snapshot rather than a delta from some base
/// config. Deltas are tidier on paper and much harder to reason about when
/// you're looking at four blocks in a row trying to work out why the third
/// one is green.
public struct TimelineSegment: Identifiable, Codable, Equatable {
    public var id: UUID
    /// Shown on the segment's block in the editor. Defaults to the
    /// snapshot's own name when created from a preset, but kept as its own
    /// field so renaming a step in the timeline doesn't rename the saved
    /// preset it came from.
    public var name: String
    public var snapshot: RingPreset
    public var length: SegmentLength
    /// Ramp up from transparent over this many seconds at the start of the
    /// segment. 0 = hard cut in.
    public var fadeIn: Double
    /// Ramp down to transparent over this many seconds at the end of the
    /// segment. 0 = hard cut out.
    public var fadeOut: Double

    public init(
        id: UUID = UUID(),
        name: String,
        snapshot: RingPreset,
        length: SegmentLength = .seconds(1.5),
        fadeIn: Double = 0,
        fadeOut: Double = 0
    ) {
        self.id = id
        self.name = name
        self.snapshot = snapshot
        self.length = length
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
    }

    /// The rate the snapshot spins at, which both length conversions above
    /// are relative to.
    public var speed: Double { snapshot.speed }

    public var duration: Double { length.duration(speed: speed) }
    public var rotations: Double { length.rotations(speed: speed) }

    /// This segment's own fade envelope at `local` seconds into it.
    ///
    /// Kept separate from `RingConfig`'s `sequenceEnvelopeOpacity` (which
    /// is the single-segment Playback section's envelope) because the two
    /// would otherwise multiply together and double-fade. A timeline plays
    /// its segments with `sequencePlaybackEnabled` forced off — see
    /// `RingTimeline.resolve(at:)`.
    public func opacity(atLocalTime local: Double) -> Double {
        let d = duration
        guard d > 0 else { return 1 }
        let t = min(max(local, 0), d)

        // When the two fades together ask for more time than the segment
        // has, they're scaled down proportionally rather than letting
        // fade-in take what it wants and starving fade-out. That makes an
        // over-long pair degrade to a triangle — ramp up to the midpoint,
        // ramp straight back down — which is what "fade in and out" should
        // approximate when there's no room to hold in between. Clamping
        // instead (the obvious first move) silently drops the fade-out
        // entirely and reads as a bug.
        let requestedIn = max(fadeIn, 0)
        let requestedOut = max(fadeOut, 0)
        let requested = requestedIn + requestedOut

        let inTime: Double
        let outTime: Double
        if requested > d, requested > 0 {
            inTime = d * (requestedIn / requested)
            outTime = d * (requestedOut / requested)
        } else {
            inTime = requestedIn
            outTime = requestedOut
        }

        if inTime > 0, t < inTime {
            return min(t / inTime, 1)
        }
        let outStart = d - outTime
        if outTime > 0, t > outStart {
            return max(1 - (t - outStart) / outTime, 0)
        }
        return 1
    }
}

/// An ordered sequence of `TimelineSegment`s — "fade in, spin three times,
/// go solid, fade out" as data.
///
/// This generalizes something the codebase already had in fixed form:
/// `LEDPatternStyle` carries `.spinThenSolidFade`,
/// `.pulseAccelerateThenSolidFade`, `.rainbowThenWhiteFade` and
/// `.transitionToSolid` as individual hardcoded cases, each one a
/// two-or-three-step sequence frozen into an enum because there was no way
/// to compose steps. Those stay exactly as they are (they're transcribed
/// from a spec sheet and shouldn't move); this is the general form for
/// building new ones.
///
/// Every method here is a pure function of time, matching `RingView`'s own
/// `overrideElapsed` contract — which is what lets `AnimationExporter`
/// render a timeline to a movie frame-by-frame without a live clock.
public struct RingTimeline: Codable, Equatable {
    public var segments: [TimelineSegment]
    /// When true, playback wraps back to 0 after `duration`. When false it
    /// holds on the final segment's last frame.
    public var loops: Bool

    public init(segments: [TimelineSegment] = [], loops: Bool = true) {
        self.segments = segments
        self.loops = loops
    }

    public var isEmpty: Bool { segments.isEmpty }

    /// Total wall-clock length of one pass through every segment.
    public var duration: Double {
        segments.reduce(0) { $0 + $1.duration }
    }

    /// The time each segment starts at, in order — index `i` is where
    /// segment `i` begins. Computed once per lookup rather than stored, so
    /// there's no cached offset to invalidate when a segment's length or
    /// speed changes.
    public var startTimes: [Double] {
        var acc: [Double] = []
        var t: Double = 0
        for segment in segments {
            acc.append(t)
            t += segment.duration
        }
        return acc
    }

    /// Cumulative rotations *before* each segment — the running total that
    /// keeps the ring's angle continuous across a boundary. See
    /// `Resolved.phaseTime` for what this is actually for.
    public var startRotations: [Double] {
        var acc: [Double] = []
        var r: Double = 0
        for segment in segments {
            acc.append(r)
            r += segment.rotations
        }
        return acc
    }

    /// Maps a raw playhead (which just counts up forever while playing)
    /// onto a position within the timeline: wrapped when looping, clamped
    /// to the ends when not.
    ///
    /// Exposed rather than kept private inside `resolve(at:)` because the
    /// editor needs the exact same number to draw its playhead and
    /// timecode. Deriving that independently is how they drift — the strip
    /// originally formatted the raw value and showed "11.88s / 6.00s" on
    /// the second lap, with the playhead pinned to the far right instead
    /// of tracking.
    public func normalizedTime(_ time: Double) -> Double {
        let total = duration
        guard total > 0 else { return 0 }
        guard loops else { return min(max(time, 0), total) }
        let wrapped = time.truncatingRemainder(dividingBy: total)
        // `truncatingRemainder` keeps the sign of the dividend, so a
        // negative playhead (possible if a scrub ever goes below zero)
        // would land outside the timeline without this.
        return wrapped < 0 ? wrapped + total : wrapped
    }

    /// Everything needed to draw one frame of the timeline.
    public struct Resolved: Equatable {
        /// Which segment is on screen, and where it sits in the array —
        /// the editor uses the index to highlight the active block.
        public var segmentIndex: Int
        public var segment: TimelineSegment
        /// Seconds into that segment.
        public var localTime: Double
        /// The segment's fade envelope at `localTime`, to apply on top of
        /// whatever the snapshot itself renders.
        public var opacity: Double
        /// What to hand `RingView(overrideElapsed:)`.
        ///
        /// **Not** the timeline's own clock. `RingView` derives the ring's
        /// angle as `elapsed × speed` (see `easedPhase`), so feeding it the
        /// raw local time would restart the rotation from angle zero at
        /// every boundary and visibly snap. Offsetting by the rotations
        /// already accumulated — converted into this segment's own time
        /// base by dividing by its speed — makes `elapsed × speed` pick up
        /// exactly where the previous segment left off, even when the two
        /// segments spin at different rates.
        ///
        /// This shifts the other elapsed-driven effects (scale pulse, hue
        /// shift, particle emission) by the same offset, which is the
        /// behavior you want for the same reason: they're continuous
        /// functions of time and shouldn't restart mid-sequence either.
        public var phaseTime: Double
    }

    /// What the ring looks like `time` seconds into the timeline.
    ///
    /// Returns `nil` only when there are no segments at all — a caller with
    /// an empty timeline should fall back to rendering the live config
    /// directly, which is what the app does before you've added a first
    /// step. Past the end of a non-looping timeline this pins to the final
    /// segment's last frame rather than returning `nil`, so the preview
    /// holds on the end state instead of blinking back to the live config.
    public func resolve(at time: Double) -> Resolved? {
        guard !segments.isEmpty else { return nil }

        let total = duration
        // Degenerate: every segment is zero-length. Show the first one
        // rather than dividing by zero below.
        guard total > 0 else {
            return Resolved(
                segmentIndex: 0,
                segment: segments[0],
                localTime: 0,
                opacity: segments[0].opacity(atLocalTime: 0),
                phaseTime: 0
            )
        }

        let t = normalizedTime(time)

        let starts = startTimes
        let rotationOffsets = startRotations

        // Last segment whose start is at or before `t`. Walking backwards
        // means the `t == total` end-pin case lands on the final segment
        // instead of falling off the front of the array.
        var index = segments.count - 1
        for i in segments.indices where starts[i] <= t {
            index = i
        }

        let segment = segments[index]
        let local = min(max(t - starts[index], 0), segment.duration)
        let speed = max(abs(segment.speed), 0.001)

        // A step replaying a recorded firmware stream gets its own local
        // time, not the rotation-accumulated offset.
        //
        // `phaseTime` exists to keep the ring's *angle* continuous across a
        // boundary — see its doc comment. A recorded stream has no angle to
        // keep continuous: its events carry absolute timestamps, and the
        // step knows where it starts via
        // `RingConfig.firmwarePatternStreamOffset`. Feeding it a rotation
        // offset instead indexed into an unrelated part of the stream, which
        // rendered as a blank ring partway through playback.
        let isStream = segment.snapshot.firmwarePatternStream != nil
        return Resolved(
            segmentIndex: index,
            segment: segment,
            localTime: local,
            opacity: segment.opacity(atLocalTime: local),
            phaseTime: isStream ? local : rotationOffsets[index] / speed + local
        )
    }
}
