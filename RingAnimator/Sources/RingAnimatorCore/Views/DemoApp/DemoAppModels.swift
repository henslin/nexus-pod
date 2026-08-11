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
public enum DemoTab: String, CaseIterable, Identifiable, Hashable, Sendable {
    case dashboard = "Dashboard"
    case feed = "Feed"
    case devices = "Devices"
    case routines = "Routines"

    public var id: String { rawValue }

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

public struct DemoCamera: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let timestamp: String
    public let systemImage: String
}

public struct DemoDeviceTile: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let status: String
    public let systemImage: String
}

public struct DemoEvent: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: String
    public let title: String
    public let subtitle: String
    public let systemImage: String
    public let hasThumbnail: Bool
}

public struct DemoMode: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let systemImage: String
    public let isActive: Bool
    public let deviceCount: String
    public let detail: String
}

/// Static sample data for the demo app screens. Deliberately generic
/// (device/event categories any smart-home app would have) rather than
/// copied from any specific reference product.
public enum DemoData {
    public static let cameras: [DemoCamera] = [
        DemoCamera(name: "Front Doorbell", timestamp: "2h ago", systemImage: "video.fill"),
        DemoCamera(name: "Driveway", timestamp: "2h ago", systemImage: "car.fill"),
        DemoCamera(name: "Backyard", timestamp: "5h ago", systemImage: "leaf.fill")
    ]

    public static let deviceTiles: [DemoDeviceTile] = [
        DemoDeviceTile(name: "Front Door", status: "Closed", systemImage: "door.left.hand.closed"),
        DemoDeviceTile(name: "Door Lock", status: "Unlocked", systemImage: "lock.open.fill"),
        DemoDeviceTile(name: "Light", status: "Off", systemImage: "lightbulb")
    ]

    public static let events: [DemoEvent] = [
        DemoEvent(timestamp: "10:00 AM", title: "Delivery", subtitle: "Driveway Camera · 0:10", systemImage: "shippingbox.fill", hasThumbnail: true),
        DemoEvent(timestamp: "10:00 AM", title: "Standby Activated", subtitle: "", systemImage: "house.slash", hasThumbnail: false),
        DemoEvent(timestamp: "9:52 AM", title: "Motion Detected", subtitle: "Hallway Sensor", systemImage: "dot.radiowaves.left.and.right", hasThumbnail: false),
        DemoEvent(timestamp: "9:40 AM", title: "Front Door Opened", subtitle: "Entry Sensor", systemImage: "door.left.hand.open", hasThumbnail: false),
        DemoEvent(timestamp: "9:15 AM", title: "Outdoor Delivery", subtitle: "Front Doorbell · 0:12", systemImage: "shippingbox.fill", hasThumbnail: true),
        DemoEvent(timestamp: "8:30 AM", title: "Arm Home Activated", subtitle: "", systemImage: "figure.walk.circle", hasThumbnail: false)
    ]

    public static let modes: [DemoMode] = [
        DemoMode(name: "Arm Away", systemImage: "house.fill", isActive: true, deviceCount: "5 Cameras",
                 detail: "Protect your home inside and out when you're away."),
        DemoMode(name: "Arm Home", systemImage: "figure.walk.circle", isActive: false, deviceCount: "No Devices",
                 detail: "Stay protected at home with devices you choose to stay armed."),
        DemoMode(name: "Standby", systemImage: "house.slash", isActive: false, deviceCount: "No Devices",
                 detail: "Disarm your devices and keep specific ones armed.")
    ]
}
