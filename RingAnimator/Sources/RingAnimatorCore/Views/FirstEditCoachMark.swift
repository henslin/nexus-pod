import SwiftUI
import Combine

/// Points at **Add Step** the first time you change a parameter.
///
/// The connection it teaches — "the thing you just tuned can be kept as a
/// step" — isn't visible from either end. The Controls panel says nothing
/// about the timeline, and the timeline's Add Step reads as "add an empty
/// step" until you know it snapshots whatever the ring currently looks
/// like. Briefly, that link was a per-section Add to Timeline button; that
/// was worse, because a step is a snapshot of the *whole* ring and a button
/// on the Motion card implied a step that carried only Motion.
///
/// Shown once, ever, and dismissed by acknowledging it or by pressing the
/// button it's pointing at — anyone who has added a step has learned the
/// thing and shouldn't be told again.
@MainActor
public final class FirstEditCoach: ObservableObject {
    private static let seenKey = "firstEditCoachSeen"

    @Published public private(set) var isShowing = false
    private var cancellable: AnyCancellable?
    private var armed = false

    public init() {}

    /// Starts watching a config for its first change.
    ///
    /// Deliberately *not* armed until a run loop turn after this is called.
    /// Binding the config, loading a preset, and the first layout pass all
    /// republish it, and treating any of those as "the user changed
    /// something" would pop the coach mark before they had touched
    /// anything.
    public func watch(_ config: RingConfig) {
        guard !UserDefaults.standard.bool(forKey: Self.seenKey) else { return }
        cancellable = config.objectWillChange
            .sink { [weak self] _ in
                guard let self, self.armed, !self.isShowing else { return }
                self.markSeen()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    self.isShowing = true
                }
            }
        DispatchQueue.main.async { [weak self] in self?.armed = true }
    }

    public func dismiss() {
        cancellable = nil
        withAnimation(.easeOut(duration: 0.2)) { isShowing = false }
    }

    /// Called when Add Step is pressed — the lesson landed, so stop
    /// pointing at it.
    public func acknowledge() {
        guard isShowing else { return }
        dismiss()
    }

    private func markSeen() {
        UserDefaults.standard.set(true, forKey: Self.seenKey)
    }

    /// So the mark can be seen again while working on it.
    public static func reset() {
        UserDefaults.standard.removeObject(forKey: Self.seenKey)
    }
}

/// The callout itself: a small bubble with a tail pointing down at the
/// button below it.
public struct FirstEditCoachMark: View {
    let onDismiss: () -> Void

    public init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Like what you changed?")
                        .font(.callout.weight(.semibold))
                    Text("Add Step keeps the ring exactly as it looks now.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.thickMaterial)
                    .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
            )

            // The tail. Drawn rather than a rotated square so it sits flush
            // against the bubble with no seam showing through the material.
            Tail()
                .fill(.thickMaterial)
                .frame(width: 16, height: 8)
                .offset(y: -0.5)
        }
        .frame(maxWidth: 290)
        .transition(.scale(scale: 0.92, anchor: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .contain)
    }

    private struct Tail: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: rect.width, y: 0))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.height))
            path.closeSubpath()
            return path
        }
    }
}
