import SwiftUI
import Combine
import TipKit

/// Points at **Add Step** the first time you change a parameter.
///
/// The connection it teaches — "the thing you just tuned can be kept as a
/// step" — isn't visible from either end. The Controls panel says nothing
/// about the timeline, and Add Step reads as "add an empty step" until you
/// know it snapshots whatever the ring currently looks like. Briefly that
/// link was an Add to Timeline button on every Controls card; that was
/// worse, because a step is a snapshot of the *whole* ring and a button on
/// the Motion card implied a step carrying only Motion.
///
/// This is `TipKit` rather than a hand-rolled callout. The first version
/// here was hand-rolled and got both of the things TipKit exists to get
/// right: it was clipped by the pane edge, because an `.overlay` can't
/// escape its parent's bounds the way a real popover can, and it sat too
/// low. TipKit also owns "shown once, ever" — no `UserDefaults` key of our
/// own to keep in step.
public struct AddStepTip: Tip {
    /// Donated on the first genuine parameter change — see
    /// `ParameterEditWatcher`, which exists to tell those apart from the
    /// republishes that happen while a view is still setting itself up.
    public static let didEditParameter = Tips.Event(id: "didEditParameter")

    public init() {}

    public var title: Text {
        Text("Like what you changed?")
    }

    public var message: Text? {
        Text("Add Step keeps the ring exactly as it looks now.")
    }

    public var image: Image? {
        Image(systemName: "sparkles")
    }

    public var rules: [Rule] {
        #Rule(Self.didEditParameter) { $0.donations.count >= 1 }
    }
}

/// Donates `AddStepTip.didEditParameter` the first time a config actually
/// changes.
///
/// The delay is the whole point. Binding the config to its player, loading
/// a preset, and the first layout pass all republish it, and treating any
/// of those as "the user changed something" pops the tip before they have
/// touched anything. Arming a run-loop turn after `watch(_:)` skips
/// exactly that burst.
@MainActor
public final class ParameterEditWatcher: ObservableObject {
    private var cancellable: AnyCancellable?
    private var armed = false

    public init() {}

    public func watch(_ config: RingConfig) {
        guard cancellable == nil else { return }
        cancellable = config.objectWillChange
            .sink { [weak self] _ in
                guard let self, self.armed else { return }
                // One donation is all the rule needs; stop listening rather
                // than donate on every slider tick for the rest of the run.
                self.cancellable = nil
                Task { await AddStepTip.didEditParameter.donate() }
            }
        DispatchQueue.main.async { [weak self] in self?.armed = true }
    }
}
