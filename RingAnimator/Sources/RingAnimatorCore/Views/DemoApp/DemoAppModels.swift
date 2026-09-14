import SwiftUI

/// The four tabs of the showcase "smart home" demo app used to preview the
/// AI ring pod living in a real app context. Content is representative
/// sample data, not wired to any backend — the point is showing the ring
/// pod + Liquid Glass tab bar sitting naturally above real, scrollable,
/// natively-navigated screens, the way they would in a shipping app.
///
/// Icons are custom-supplied assets (bundled in `Resources/TabIcons.xcassets`,
/// `template-rendering-intent: template` so they tint like SF Symbols do),
/// each with a distinct outline (unselected) and filled (selected) variant.
public enum DemoTab: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case dashboard = "Dashboard"
    case feed = "Feed"
    case devices = "Devices"
    case routines = "Routines"

    public var id: String { rawValue }

    /// The artwork pair's base name — `outlineImageName` and
    /// `filledImageName` are this plus a suffix. Separate from `rawValue`
    /// so an edited display name can never change which asset is loaded.
    public var artworkBaseName: String {
        switch self {
        case .dashboard: return "dashboard"
        case .feed: return "feed"
        case .devices: return "devices"
        case .routines: return "routines"
        }
    }

    /// Asset name for the unselected (outline) state.
    public var outlineImageName: String {
        switch self {
        case .dashboard: return "dashboard-outline"
        case .feed: return "feed-outline"
        case .devices: return "devices-outline"
        case .routines: return "routines-outline"
        }
    }

    /// Asset name for the selected (filled) state.
    public var filledImageName: String {
        switch self {
        case .dashboard: return "dashboard-filled"
        case .feed: return "feed-filled"
        case .devices: return "devices-filled"
        case .routines: return "routines-filled"
        }
    }

    /// Pre-built `Image`s loaded from `RingAnimatorCore`'s own resource
    /// bundle. Call these rather than constructing `Image(name:, bundle:
    /// .module)` yourself from outside this module — the generated
    /// `Bundle.module` accessor is only visible inside the target that
    /// declares the resources (`RingAnimatorCore`), so it can't be
    /// referenced directly from `TabBarPreview` (a different target) or
    /// the real iOS app (a separate Xcode project entirely).
    public var outlineImage: Image { Image(outlineImageName, bundle: .module) }
    public var filledImage: Image { Image(filledImageName, bundle: .module) }

    /// A full-screen reference screenshot of the real app UI for this tab
    /// (bundled in `Resources/DemoScreens.xcassets`), used as an
    /// alternative to the hand-built `Demo*TabView` content in the phone
    /// mockup — real screenshots make Liquid Glass refraction on the tab
    /// bar read correctly (there's genuine detail behind it to bend), and
    /// save building out full UI for every screen.
    public func screenshotImage(dark: Bool) -> Image {
        let name = "\(rawValue.lowercased())-\(dark ? "dark" : "light")"
        return Image(name, bundle: .module)
    }
}

/// A tab's icon: either one of the bundled artwork pairs or an SF Symbol.
///
/// Artwork comes in outline/filled pairs (`dashboard-outline` /
/// `dashboard-filled`) because that is how the supplied set is drawn.
/// Symbols use the *same* glyph in both states rather than guessing at a
/// `.fill` variant — the guess would silently draw nothing whenever that
/// variant doesn't exist, and selection is already carried by the pill and
/// the ink colour.
public enum TabGlyph: Codable, Sendable, Equatable, Hashable {
    case artwork(String)
    case symbol(String)

    /// The bundled pairs in `Resources/TabIcons.xcassets`. Hardcoded
    /// because an asset catalog can't be enumerated at runtime; add a pair
    /// to the catalog and it must be added here too or it won't be offered.
    public static let bundledArtwork = ["dashboard", "feed", "devices", "routines"]

    /// `Bundle.module` is only visible inside the target that declares the
    /// resources, which is why this lives here rather than in
    /// `TabBarPreview` — same reason `DemoTab.outlineImage` does.
    public func image(selected: Bool) -> Image {
        switch self {
        case .artwork(let base):
            return Image("\(base)-\(selected ? "filled" : "outline")", bundle: .module)
        case .symbol(let name):
            return Image(systemName: name)
        }
    }
}

/// A tab's editable name and icon.
///
/// **Separate from `DemoTab` on purpose.** `DemoTab` is the stable
/// identity: its `rawValue` keys the bundled screenshots
/// (`screenshotImage(dark:)` builds `"dashboard-dark"` from it) and the
/// exporter's `appUI(tab:)`. Letting an edited name drive that would mean
/// renaming a tab silently broke which screenshot it shows. So the name
/// you can change and the name the assets are filed under are two
/// different things, deliberately.
public struct TabAppearance: Codable, Sendable, Equatable, Identifiable {
    public var slot: DemoTab
    public var name: String
    public var glyph: TabGlyph

    public var id: DemoTab { slot }

    public init(slot: DemoTab, name: String, glyph: TabGlyph) {
        self.slot = slot
        self.name = name
        self.glyph = glyph
    }

    /// What a tab looks like before anyone edits it — the enum's own name
    /// and its own artwork, so the default state is exactly what the app
    /// shipped with.
    public static func `default`(for slot: DemoTab) -> TabAppearance {
        TabAppearance(slot: slot, name: slot.rawValue, glyph: .artwork(slot.artworkBaseName))
    }

    public static var defaults: [TabAppearance] {
        DemoTab.allCases.map { .default(for: $0) }
    }
}

/// A handful of generic layout constants shared by the demo screens —
/// ordinary iOS conventions (16pt margins, 20pt card corners), not values
/// extracted from any specific design.
public enum DemoLayout {
    public static let pageMargin: CGFloat = 16
    public static let cardCornerRadius: CGFloat = 20
    public static let rowSpacing: CGFloat = 12
}

/// Adaptive system colors for the demo screens. Using the platform's
/// semantic grouped-background colors (rather than fixed hex values) means
/// these automatically follow whatever `colorScheme` is applied to the
/// view tree — including the light/dark toggle on the phone mockup.
public enum DemoColors {
    public static var pageBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    public static var cardBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    public static var mutedFill: Color {
        #if os(iOS)
        Color(uiColor: .tertiarySystemFill)
        #else
        Color.primary.opacity(0.06)
        #endif
    }

    public static let accent = Color.red
}
