import Foundation

/// One frame of timeline playback, as a plain value: what elapsed time to
/// render the ring at, and how far faded it is.
///
/// This is the whole contract between "a timeline is playing" and every
/// view that draws a ring. Passing a value (rather than handing views a
/// `TimelinePlayer` to observe) keeps the drawing path a pure function of
/// its inputs — the same reason `RingView` takes `overrideElapsed` instead
/// of reading a clock, and what makes frame-by-frame movie export possible
/// without a live playhead.
///
/// `nil` anywhere this is accepted means "no timeline" and restores the
/// original behavior exactly: the ring free-runs on its own animation
/// clock at full opacity.
public struct TimelinePlayback: Equatable {
    /// What to hand `RingView(overrideElapsed:)` — the phase-continuous
    /// time base, not the raw playhead. See
    /// `RingTimeline.Resolved.phaseTime` for why those differ.
    public var elapsed: Double
    /// The active segment's fade envelope, 0...1.
    public var opacity: Double

    public init(elapsed: Double, opacity: Double) {
        self.elapsed = elapsed
        self.opacity = opacity
    }

    /// Lifts a resolved timeline frame into the value views actually take.
    public init(_ resolved: RingTimeline.Resolved) {
        self.elapsed = resolved.phaseTime
        self.opacity = resolved.opacity
    }
}
