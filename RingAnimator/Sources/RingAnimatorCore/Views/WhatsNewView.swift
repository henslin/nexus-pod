import SwiftUI

/// One line item on the What's New screen.
public struct WhatsNewItem: Identifiable, Sendable {
    public let id = UUID()
    public let symbol: String
    public let title: String
    public let detail: String

    public init(symbol: String, title: String, detail: String) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
    }
}

/// The "What's New in ..." screen Apple shows after an update: a big title,
/// a short list of features each with a symbol, and one button out.
///
/// Shared by both apps, which is the point — the Mac tool and the iOS app
/// ship the same release notes rather than two hand-kept copies that drift.
/// Platform differences are confined to `padding` and how it's presented
/// (a fixed-width sheet on Mac, a full-height one on iOS).
///
/// **The copy in `WhatsNew.current` is placeholder.** It's real enough to
/// read as a genuine release note — it describes work that actually landed
/// — but nobody has edited it for tone or decided what a release is
/// actually called. Replace it, don't extend it: four or five items is the
/// shape Apple uses, and a list that grows every sprint stops being read.
public struct WhatsNewView: View {
    let appName: String
    let items: [WhatsNewItem]
    let onDismiss: () -> Void

    public init(
        appName: String = "Nexus Pod",
        items: [WhatsNewItem] = WhatsNew.current,
        onDismiss: @escaping () -> Void
    ) {
        self.appName = appName
        self.items = items
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Scrolls only when it has to. Five items on a 560pt sheet fit
            // with room to spare, and a scroll view that never scrolls
            // still eats the bounce and hides the fact that this is the
            // whole list — the system's own screens don't scroll either
            // until the text size makes them. `ViewThatFits` tries the
            // plain stack first and falls back.
            //
            // It also makes the screen renderable offscreen: `ImageRenderer`
            // lays out a `ScrollView`'s content as empty, so the version
            // that always scrolled could not be checked without running the
            // app and looking at it.
            ViewThatFits(in: .vertical) {
                content
                ScrollView { content }
            }

            continueButton
                .padding(.horizontal, 28)
                .padding(.bottom, 22)
                .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        // 660, not 560. At 560 the five items plus the title overflowed and
        // `ViewThatFits` fell back to the scrolling branch — a sheet with
        // its own scroll bar for content that should simply be on screen.
        // Measured by rendering it, not guessed: the static branch is what
        // renders now, which is how you can tell it fits.
        .frame(width: 440, height: 660)
        #endif
    }

    private var content: some View {
        VStack(spacing: 0) {
            title
                .padding(.top, titleTopPadding)
                .padding(.bottom, 36)

            VStack(alignment: .leading, spacing: 26) {
                ForEach(items) { item in
                    row(item)
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity)
    }

    private var title: some View {
        // "What's New in" small above the app name, both centered — the
        // arrangement the system uses, rather than one long wrapped line.
        VStack(spacing: 2) {
            Text("What's New in")
            Text(appName)
        }
        .font(.system(size: 34, weight: .bold, design: .default))
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ item: WhatsNewItem) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: item.symbol)
                .font(.system(size: 26))
                .foregroundStyle(Color.accentColor)
                // Fixed width so every title starts at the same x no matter
                // how wide its symbol happens to draw.
                .frame(width: 36, alignment: .center)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.headline)
                Text(item.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var continueButton: some View {
        Button(action: onDismiss) {
            Text("Continue")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
    }

    private var titleTopPadding: CGFloat {
        #if os(macOS)
        44
        #else
        56
        #endif
    }
}

/// The release notes both apps show.
public enum WhatsNew {

    /// Bump this when the notes change. The screen shows itself once per
    /// value, so editing the copy without bumping it means nobody who has
    /// already dismissed the old notes ever sees the new ones.
    public static let version = "3.0"

    public static let current: [WhatsNewItem] = [
        WhatsNewItem(
            symbol: "iphone",
            title: "Export With the App Around It",
            detail: "Put the animation on a real phone screen — your choice of tab, light or dark, and Apple's iPhone 17 Pro in Silver, Deep Blue or Cosmic Orange. Drops straight into a deck."
        ),
        WhatsNewItem(
            symbol: "square.on.square.dashed",
            title: "Transparent Backgrounds",
            detail: "Export the ring with a real alpha channel — no black square around it in Figma, and it plays transparent in Keynote or in an app."
        ),
        WhatsNewItem(
            symbol: "sparkles",
            title: "Particles You Can Export",
            detail: "Particles are simulated where nothing can render them frame by frame, so the app records them from the live preview instead."
        ),
        WhatsNewItem(
            symbol: "square.stack.3d.up",
            title: "Apply to All",
            detail: "Change one animation — Smooth, particles, speed, anything — and push exactly those changes onto the whole list in one go."
        ),
        WhatsNewItem(
            symbol: "shippingbox",
            title: "The Library Comes With the App",
            detail: "Every use case ships inside, dated so you can see how current it is. A new version adds what's new and updates what you haven't touched — anything you've edited is left exactly as you left it."
        ),
    ]
}

/// Decides whether the What's New screen is due.
///
/// Once per `WhatsNew.version` per install, which is the behavior the
/// system screens have: shown after an update, never again until the next
/// one. Deliberately *not* shown on a genuinely fresh install — someone
/// opening the app for the first time has no idea what's new relative to
/// what, and the list reads as a feature tour they didn't ask for.
@MainActor
public enum WhatsNewPresenter {
    private static let seenKey = "whatsNewSeenVersion"
    private static let launchedKey = "hasLaunchedBefore"

    public static func shouldPresent() -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: launchedKey) else {
            // First ever launch: record both, show nothing.
            defaults.set(true, forKey: launchedKey)
            defaults.set(WhatsNew.version, forKey: seenKey)
            return false
        }
        return defaults.string(forKey: seenKey) != WhatsNew.version
    }

    public static func markSeen() {
        UserDefaults.standard.set(WhatsNew.version, forKey: seenKey)
    }

    /// For the menu item — showing it on demand shouldn't depend on, or
    /// change, whether it's due.
    public static func reset() {
        UserDefaults.standard.removeObject(forKey: seenKey)
    }
}
