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
            ScrollView {
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

            continueButton
                .padding(.horizontal, 28)
                .padding(.bottom, 22)
                .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .frame(width: 440, height: 560)
        #endif
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
    public static let version = "2.2"

    /// PLACEHOLDER COPY — see `WhatsNewView`'s doc comment.
    public static let current: [WhatsNewItem] = [
        WhatsNewItem(
            symbol: "drop.halffull",
            title: "Smooth",
            detail: "The same hardware-accurate animation, spread in space and trailed in time — one continuous gradient instead of twenty hard edges."
        ),
        WhatsNewItem(
            symbol: "tray.and.arrow.down",
            title: "Import a Whole Library",
            detail: "Point at a folder of firmware patterns and get one use case per file, with their palettes, timings and phase steps."
        ),
        WhatsNewItem(
            symbol: "rectangle.3.group",
            title: "One Preview, Everywhere",
            detail: "The zoomable phone mockup is now the canvas in every section, and it keeps its place when you switch between them."
        ),
        WhatsNewItem(
            symbol: "bolt.fill",
            title: "Much Lighter",
            detail: "The ring draws about four times faster, and the app no longer keeps a CPU core busy while sitting still."
        ),
        WhatsNewItem(
            symbol: "arrow.uturn.backward",
            title: "Reset and Add to Timeline",
            detail: "Every section of the controls can be put back to its defaults, or committed to the timeline as a step."
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
