import SwiftUI

// The app's top-level screens, natively — from the Nexus Neue file's
// "App Wide" page (25696:19216): Dashboard, Feed, Emergency, Devices,
// Routines, in light and dark, built with Liquid Glass and the file's
// own glyphs. They read the same `QuidgetDemo` the agent writes, so
// when the agent arms the house, the arm bar on the dashboard, the
// Routines cards and the Feed all show it (Chris, 2026-09-17: "when
// you arm with the AI agent, that UI will have to update too").
//
// Every measure below is the file's. Colours are its tokens, light and
// dark: background primary/secondary/tertiary, text primary/secondary,
// fill primary/secondary/warning/action.

/// The five tabs of the file's tab bar.
public enum NexusTab: String, CaseIterable, Identifiable, Sendable {
    case dashboard, feed, emergency, devices, routines
    public var id: String { rawValue }
    var label: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .feed: return "Feed"
        case .emergency: return "Emergency"
        case .devices: return "Devices"
        case .routines: return "Routines"
        }
    }
    var glyph: (on: NexusGlyph, off: NexusGlyph) {
        switch self {
        case .dashboard: return (.tabDashboard, .tabDashboardOutline)
        case .feed: return (.tabFeed, .tabFeedOutline)
        case .emergency: return (.tabEmergency, .tabEmergencyOutline)
        case .devices: return (.tabDevices, .tabDevicesOutline)
        case .routines: return (.tabRoutines, .tabRoutinesOutline)
        }
    }
    /// This tab in the app's older four-tab model — Emergency has no
    /// counterpart there and shows as the dashboard's bar.
    public var demoTab: DemoTab {
        switch self {
        case .dashboard, .emergency: return .dashboard
        case .feed: return .feed
        case .devices: return .devices
        case .routines: return .routines
        }
    }
    /// The app's older four-tab model, mapped.
    public init(_ tab: DemoTab) {
        switch tab {
        case .dashboard: self = .dashboard
        case .feed: self = .feed
        case .devices: self = .devices
        case .routines: self = .routines
        }
    }
}

/// The file's tokens, by appearance.
struct NexusInk {
    let dark: Bool
    var bgPrimary: Color { dark ? .black : Color(hex: "#F2F2F6") }
    var bgSecondary: Color { dark ? Color(hex: "#191919") : .white }
    var bgTertiary: Color { dark ? Color(hex: "#404040") : Color(hex: "#E8E8EB") }
    var textPrimary: Color { dark ? .white : Color(hex: "#404040") }
    var textSecondary: Color { dark ? Color(hex: "#E8E8EB") : Color(hex: "#636466") }
    var fillPrimary: Color { dark ? Color(hex: "#C6C6CF") : Color(hex: "#636466") }
    var fillSecondary: Color { Color(hex: "#8E919E") }
    var warning: Color { dark ? Color(hex: "#EA333A") : Color(hex: "#D22434") }
    var action: Color { dark ? Color(hex: "#4DA3D6") : Color(hex: "#055E88") }
    var caution: Color { Color(hex: "#F8B541") }
    /// The tab bar's pill and the nav bar's buttons, flat: the file's
    /// #F7F7F7 over white-at-50%, and its dark counterpart.
    var chrome: Color { dark ? Color(hex: "#2C2C2E") : Color(hex: "#F7F7F7") }
    var chromeActive: Color { dark ? Color(hex: "#4A4A4C") : .white }
}

/// The screen: one tab of the app, at the phone's size, with or without
/// the file's tab bar (the Lab draws its own, with the pod).
public struct NexusScreen: View {
    public let tab: NexusTab
    @ObservedObject var home: QuidgetDemo
    public var size: CGSize = CGSize(width: 402, height: 874)
    public var showsTabBar = true
    @Environment(\.colorScheme) private var scheme

    public init(tab: NexusTab, home: QuidgetDemo, size: CGSize = CGSize(width: 402, height: 874), showsTabBar: Bool = true) {
        self.tab = tab
        self.home = home
        self.size = size
        self.showsTabBar = showsTabBar
    }

    public var body: some View {
        let ink = NexusInk(dark: scheme == .dark)
        ZStack(alignment: .top) {
            ink.bgPrimary
            Group {
                switch tab {
                case .dashboard: NexusDashboard(home: home, ink: ink, width: size.width)
                case .feed: NexusFeed(home: home, ink: ink, width: size.width)
                case .emergency: NexusEmergency(ink: ink, size: size)
                case .devices: NexusDevices(home: home, ink: ink, width: size.width)
                case .routines: NexusRoutines(home: home, ink: ink, width: size.width)
                }
            }
            .padding(.top, NexusNavBar.height)
            NexusNavBar(ink: ink, width: size.width, avatar: tab == .routines)
            if showsTabBar {
                NexusTabBar(selected: tab, ink: ink, width: size.width)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

// MARK: - Chrome

/// The status bar and the toolbar: 62 + 54.
struct NexusNavBar: View {
    let ink: NexusInk
    let width: CGFloat
    var avatar = false
    static let height: CGFloat = 120
    /// The Dynamic Island's left edge and centre line, in points on the
    /// 402-wide screen — measured off the device frame's image.
    static let islandX: CGFloat = 139
    static let islandCenterY: CGFloat = 32
    /// "12:27" — the status bar shows no AM/PM.
    static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            // The status bar sits either side of the Dynamic Island —
            // measured in the frame at x 139–263, y 15–50 on the 402-wide
            // screen — the time centred in the left ear, the icons in the
            // right, both on the island's centre line. The time is the
            // real time (Chris, 2026-09-18), on a clock that ticks each
            // minute.
            let ear = Self.islandX * width / 402
            HStack(spacing: 0) {
                TimelineView(.everyMinute) { t in
                    Text(Self.clock.string(from: t.date)).font(.system(size: 17, weight: .semibold))
                }
                .frame(width: ear)
                Spacer(minLength: 0)
                HStack(spacing: 7) {
                    Image(systemName: "cellularbars").font(.system(size: 14, weight: .semibold))
                    Image(systemName: "wifi").font(.system(size: 14, weight: .semibold))
                    Image(systemName: "battery.100percent").font(.system(size: 17, weight: .regular))
                }
                .frame(width: ear)
            }
            .foregroundStyle(ink.dark ? .white : .black)
            .frame(height: Self.islandCenterY * 2)
            .frame(height: 62, alignment: .top)
            // The toolbar, 4 pt further from the island than the status
            // band alone leaves.
            HStack(alignment: .top, spacing: 0) {
                NexusGlassPill(ink: ink) {
                    Group {
                        if avatar {
                            Image("nexus-avatar", bundle: .module).resizable().scaledToFill()
                                .frame(width: 25, height: 25).clipShape(Circle())
                        } else {
                            Image(systemName: "person.fill").font(.system(size: 17, weight: .medium))
                        }
                    }
                    .frame(width: 44, height: 44)
                }
                .padding(2)
                Spacer(minLength: 0)
                NexusGlassPill(ink: ink) {
                    HStack(spacing: 6) {
                        Text("Smith Home").font(.system(size: 15, weight: .semibold)).tracking(-0.23)
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(ink.bgTertiary))
                    }
                    .padding(.leading, 14).padding(.trailing, 10).padding(.vertical, 13)
                }
                Spacer(minLength: 0)
                NexusGlassPill(ink: ink) {
                    HStack(spacing: -2) {
                        Image(systemName: "plus").font(.system(size: 17, weight: .medium)).frame(width: 44, height: 44)
                        Image(systemName: "ellipsis").font(.system(size: 17, weight: .medium)).frame(width: 44, height: 44)
                    }
                    .padding(.horizontal, 4).padding(.vertical, 2)
                }
            }
            .foregroundStyle(ink.textPrimary)
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 10)
            .frame(height: 58)
        }
        .frame(width: width, height: Self.height)
    }
}

/// The file's ".Leading / .Title / .Trailing" pills: Liquid Glass, or
/// the flat chrome colour where glass can't draw.
struct NexusGlassPill<Content: View>: View {
    let ink: NexusInk
    @ViewBuilder let content: () -> Content
    @Environment(\.labNoGlass) private var noGlass

    var body: some View {
        Group {
            if noGlass {
                content().background(Capsule().fill(ink.chrome))
            } else if #available(iOS 26.0, macOS 26.0, *) {
                content().glassEffect(.regular.tint(ink.chrome.opacity(0.6)), in: Capsule())
            } else {
                content().background(.regularMaterial, in: Capsule())
            }
        }
        .shadow(color: .black.opacity(0.04), radius: 20)
    }
}

/// The file's tab bar: a 62-tall glass capsule, four in from the
/// edges, five items; the active one on its own pill.
struct NexusTabBar: View {
    let selected: NexusTab
    let ink: NexusInk
    let width: CGFloat
    static let height: CGFloat = 95

    var body: some View {
        NexusGlassPill(ink: ink) {
            HStack(spacing: -5.5) {
                ForEach(NexusTab.allCases) { tab in
                    let on = tab == selected
                    VStack(spacing: -2) {
                        NexusGlyphView(on ? tab.glyph.on : tab.glyph.off, color: on ? (ink.dark ? .white : .black) : ink.textPrimary)
                            .frame(width: 30, height: 30)
                        Text(tab.label)
                            .font(.system(size: 10, weight: on ? .semibold : .medium)).tracking(-0.1)
                            .foregroundStyle(on ? (ink.dark ? .white : .black) : ink.textPrimary)
                            .lineLimit(1)
                    }
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Capsule().fill(on ? ink.chromeActive : .clear))
                }
            }
            .padding(4)
            .frame(height: 62)
        }
        .padding(.horizontal, 21)
        .padding(.top, 12).padding(.bottom, 21)
        .frame(width: width, height: Self.height)
        .background(LinearGradient(colors: [ink.bgPrimary.opacity(0), ink.bgPrimary.opacity(0.65)], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.8)))
    }
}

// MARK: - Dashboard

struct NexusDashboard: View {
    @ObservedObject var home: QuidgetDemo
    let ink: NexusInk
    let width: CGFloat

    var body: some View {
        VStack(spacing: 8) {
            NexusArmBar(home: home, ink: ink)
                .padding(.bottom, 8)
            NexusCustomModeWidget(ink: ink)
            NexusCameraCard(image: "nexus-kitchen", name: "Camera Name", size: CGSize(width: width - 32, height: 208), ink: ink)
            HStack(spacing: 10) {
                NexusDeviceWidget(glyph: .door, tint: ink.fillPrimary, title: "Front Door", status: "Closed", ink: ink)
                NexusDeviceWidget(glyph: .lock, tint: home.locked ? Color(hex: "#6CB189") : ink.caution, title: "Door Lock", status: home.locked ? "Locked" : "Unlocked", ink: ink)
                NexusDeviceWidget(glyph: .light, tint: home.lightLevel > 0 ? ink.caution : ink.fillPrimary, title: "Light", status: home.lightLevel > 0 ? "\(Int((home.lightLevel * 100).rounded()))%" : "Off", ink: ink)
            }
            HStack(spacing: 10) {
                NexusCameraCard(image: "nexus-driveway", name: "Camera Name", size: CGSize(width: 181, height: 110), ink: ink, small: true)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .frame(width: width)
    }
}

/// The arm bar: three modes in the tertiary well, the active one on the
/// warning red — and, while the house is arming, the mode on its way
/// spins where its glyph will land.
struct NexusArmBar: View {
    @ObservedObject var home: QuidgetDemo
    let ink: NexusInk

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SecurityMode.allCases) { mode in
                let on = home.mode == mode
                VStack(spacing: 8) {
                    ZStack {
                        Circle().fill(on ? ink.warning : ink.bgSecondary)
                        if home.arming == mode {
                            QuidgetSpinnerView(color: on ? .white : ink.fillSecondary)
                                .frame(width: 28, height: 28)
                                .transition(.scale.combined(with: .opacity))
                        } else {
                            NexusGlyphView(mode.nexusGlyph, color: on ? .white : ink.fillSecondary)
                                .frame(width: 42.67, height: 42.67)
                                .padding(.bottom, 4.5)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .frame(width: 64, height: 64)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: home.arming == mode)
                    Text(mode.label)
                        .font(.system(size: 13, weight: .semibold)).tracking(-0.08)
                        .foregroundStyle(on ? ink.textPrimary : ink.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { home.setMode(mode) }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 15)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(ink.bgTertiary))
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: home.mode)
    }
}

extension SecurityMode {
    var nexusGlyph: NexusGlyph {
        switch self {
        case .armAway: return .modeArmAway
        case .armHome: return .modeArmHome
        case .standby: return .modeStandby
        }
    }
    var feedTint: Color {
        switch self {
        case .armAway: return Color(hex: "#D22434")
        case .armHome: return Color(hex: "#F8B541")
        case .standby: return Color(hex: "#33CC99")
        }
    }
}

struct NexusCustomModeWidget: View {
    let ink: NexusInk
    var body: some View {
        HStack(spacing: 12) {
            NexusGlyphView(.modeCustom, color: ink.fillSecondary)
                .frame(width: 32, height: 32)
                .padding(.bottom, 4)
                .frame(width: 52, height: 52)
                .background(Circle().fill(ink.bgSecondary))
            Text("Custom Mode").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ink.textPrimary)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ink.textPrimary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(ink.bgSecondary))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(ink.bgTertiary))
    }
}

/// The file's Camera Card: the frame, a gradient top and bottom, "2h
/// ago" and the settings glass at the top, Go Live in the middle, the
/// name and the indicator pill at the bottom. Small: 44-tall bars.
struct NexusCameraCard: View {
    let image: String
    let name: String
    let size: CGSize
    let ink: NexusInk
    var small = false
    @Environment(\.labNoGlass) private var noGlass

    var body: some View {
        let bar: CGFloat = small ? 44 : 80
        ZStack {
            Image(image, bundle: .module).resizable().scaledToFill()
                .frame(width: size.width, height: size.height).clipped()
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    Text("2h ago").font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                    Spacer(minLength: 0)
                    if !small {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 12.36, weight: .medium)).foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .modifier(NexusDarkGlass(shape: Circle(), noGlass: noGlass))
                    }
                }
                .padding(small ? 10 : 16).padding(.horizontal, small ? 2 : 0)
                .frame(height: bar, alignment: .top)
                .background(LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom))
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 16) {
                    Text(name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    Spacer(minLength: 0)
                    HStack(spacing: 8) {
                        NexusGlyphView(.battery, color: .white).frame(width: 16, height: 16)
                        if !small {
                            NexusGlyphView(.wifi, color: .white).frame(width: 16, height: 16)
                            NexusGlyphView(.motion, color: .white).frame(width: 16, height: 16)
                            NexusGlyphView(.sound, color: .white).frame(width: 16, height: 16)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.2)))
                }
                .padding(small ? 10 : 16).padding(.horizontal, small ? 2 : 0)
                .frame(height: bar, alignment: .bottom)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom))
            }
            Text("Go Live").font(.system(size: 15, weight: .semibold)).tracking(-0.23).foregroundStyle(.white)
                .padding(.horizontal, 20)
                .frame(height: small ? 32 : 36)
                .modifier(NexusDarkGlass(shape: Capsule(), noGlass: noGlass))
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

/// The file's dark glass over a picture: black at 20% on a blur.
struct NexusDarkGlass<S: Shape>: ViewModifier {
    let shape: S
    let noGlass: Bool
    func body(content: Content) -> some View {
        if noGlass {
            content.background(shape.fill(Color.black.opacity(0.35)))
        } else if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular.tint(Color.black.opacity(0.2)), in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
        }
    }
}

/// The file's Dashboard Widget / Device Card: glyph and settings on
/// top, name and status at the bottom, 110 tall.
struct NexusDeviceWidget: View {
    let glyph: NexusGlyph
    let tint: Color
    let title: String
    let status: String
    let ink: NexusInk

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                NexusGlyphView(glyph, color: tint).frame(width: 32, height: 32)
                Spacer(minLength: 0)
                NexusGlyphView(.settings, color: ink.fillPrimary).frame(width: 32, height: 32)
            }
            Spacer(minLength: 0)
            Text(title).font(.system(size: 13, weight: .semibold)).tracking(-0.08).foregroundStyle(ink.textPrimary).lineLimit(1)
            Text(status).font(.system(size: 13, weight: .semibold)).tracking(-0.08).foregroundStyle(ink.textSecondary).lineLimit(1)
                .frame(height: 18)
                .contentTransition(.numericText())
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .frame(height: 110)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(ink.bgSecondary))
        .animation(.easeInOut(duration: 0.3), value: status)
    }
}

// MARK: - Feed

struct NexusFeed: View {
    @ObservedObject var home: QuidgetDemo
    let ink: NexusInk
    let width: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 4) {
                    Text("Today, September 9").font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold)).frame(width: 20, height: 20)
                }
                .foregroundStyle(ink.textPrimary)
                .padding(.leading, 12).padding(.trailing, 8).padding(.vertical, 7)
                .background(Capsule().fill(ink.bgTertiary))
                Spacer(minLength: 0)
                HStack(spacing: -2) {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 15, weight: .medium)).frame(width: 44, height: 44)
                    Text("Filter").font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(ink.textPrimary)
                .padding(.trailing, 12)
                .frame(height: 34)
                .background(Capsule().fill(ink.bgTertiary))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            VStack(spacing: 10) {
                // The latest event is the house's mode — the one the agent
                // just set, when it did.
                modeRow("\(home.mode.label) Activated", time: home.arming == nil ? "Just now" : "10:00 AM", mode: home.mode)
                clipRow("Delivery", camera: "Driveway Camera", image: "nexus-feed-car")
                clipRow("Essential Kid", camera: "Hallway", image: "nexus-feed-kid")
                plainRow("High Temperature", subtitle: "Hallway Sensor") {
                    HStack(alignment: .top, spacing: 1) {
                        NexusGlyphView(.temperature, color: ink.fillPrimary).frame(width: 20, height: 20).padding(.top, 6)
                        Text("72").font(.system(size: 24)).foregroundStyle(ink.fillPrimary)
                        Text("°F").font(.system(size: 12)).foregroundStyle(ink.fillPrimary).padding(.top, 3)
                    }
                }
                plainRow("Motion", subtitle: "Hallway Sensor") {
                    NexusGlyphView(.motionEvent, color: ink.fillPrimary).frame(width: 32, height: 32)
                }
                clipRow("Outdoor Delivery", camera: "Outdoor", image: "nexus-feed-outdoor")
                modeRow("Arm Home Activated", time: "10:00 AM", mode: .armHome)
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 10)
        .frame(width: width)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: home.mode)
    }

    private func clipRow(_ title: String, camera: String, image: String) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text("10:00 AM").font(.system(size: 13)).foregroundStyle(ink.textSecondary)
                Text(title).font(.system(size: 17, weight: .semibold)).tracking(-0.43).foregroundStyle(ink.textPrimary)
                Text("\(camera) | 0:10").font(.system(size: 13)).tracking(-0.08).foregroundStyle(ink.textSecondary).frame(height: 18)
            }
            Spacer(minLength: 0)
            Image(image, bundle: .module).resizable().scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(ink.bgSecondary))
    }

    private func modeRow(_ title: String, time: String, mode: SecurityMode) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(time).font(.system(size: 13)).tracking(-0.08).foregroundStyle(ink.textSecondary)
                Text(title).font(.system(size: 17, weight: .semibold)).tracking(-0.43).foregroundStyle(ink.textPrimary)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
            NexusGlyphView(mode.nexusGlyph, color: mode.feedTint).frame(width: 40, height: 40)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func plainRow<Trailing: View>(_ title: String, subtitle: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text("10:00 AM").font(.system(size: 13)).tracking(-0.08).foregroundStyle(ink.textSecondary)
                Text(title).font(.system(size: 17, weight: .semibold)).tracking(-0.43).foregroundStyle(ink.textPrimary)
                Text(subtitle).font(.system(size: 13)).tracking(-0.08).foregroundStyle(ink.textSecondary)
            }
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

// MARK: - Devices

struct NexusDevices: View {
    @ObservedObject var home: QuidgetDemo
    let ink: NexusInk
    let width: CGFloat

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("Front Door").font(.system(size: 15, weight: .semibold)).tracking(-0.23).foregroundStyle(ink.textPrimary)
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(ink.textPrimary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(ink.bgTertiary))
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            NexusCameraCard(image: "nexus-doorbell", name: "Doorbell", size: CGSize(width: width - 32, height: width - 32), ink: ink)
            NexusCameraCard(image: "nexus-kitchen", name: "Camera Name", size: CGSize(width: width - 32, height: 208), ink: ink)
            HStack(spacing: 8) {
                NexusDeviceWidget(glyph: .door, tint: ink.fillPrimary, title: "Front Door", status: "Closed", ink: ink)
                NexusDeviceWidget(glyph: .lock, tint: home.locked ? Color(hex: "#6CB189") : ink.caution, title: "Door Lock", status: home.locked ? "Locked" : "Unlocked", ink: ink)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .frame(width: width)
    }
}

// MARK: - Routines

struct NexusRoutines: View {
    @ObservedObject var home: QuidgetDemo
    let ink: NexusInk
    let width: CGFloat

    var body: some View {
        VStack(spacing: 16) {
            // The file's segmented control: the chosen segment on a white
            // pill with a soft shadow.
            HStack(spacing: 0) {
                ForEach(Array(["Modes", "Automations", "Shortcuts"].enumerated()), id: \.offset) { i, s in
                    if i > 0 { Rectangle().fill(ink.fillSecondary.opacity(0.3)).frame(width: 1, height: 24) }
                    Text(s).font(.system(size: 14, weight: i == 0 ? .semibold : .medium)).tracking(-0.08)
                        .foregroundStyle(ink.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .background {
                            if i == 0 { Capsule().fill(ink.bgSecondary).shadow(color: .black.opacity(0.06), radius: 10, y: 2) }
                        }
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .frame(height: 32)
            .background(Capsule().fill(ink.bgTertiary))
            VStack(spacing: 8) {
                ForEach(SecurityMode.allCases) { mode in
                    modeCard(mode)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .frame(width: width)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: home.mode)
    }

    private func modeCard(_ mode: SecurityMode) -> some View {
        let on = home.mode == mode
        return VStack(spacing: 0) {
            HStack(spacing: 16) {
                ZStack {
                    Circle().fill(on ? ink.warning : ink.bgTertiary)
                    if home.arming == mode {
                        QuidgetSpinnerView(color: on ? .white : ink.fillSecondary).frame(width: 18, height: 18)
                    } else {
                        NexusGlyphView(mode.nexusGlyph, color: on ? .white : ink.fillSecondary)
                            .frame(width: 24, height: 24).padding(.bottom, 2)
                    }
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .lastTextBaseline, spacing: 5) {
                        Text(mode.label).font(.system(size: 17)).tracking(-0.43).foregroundStyle(ink.textPrimary)
                        if on {
                            Text("Active").font(.system(size: 12, weight: .medium)).foregroundStyle(ink.action)
                                .transition(.opacity)
                        }
                    }
                    Text(on ? "5 Cameras" : "No Devices").font(.system(size: 12)).foregroundStyle(ink.textSecondary)
                }
                Spacer(minLength: 0)
                NexusGlyphView(.chevron, color: ink.fillSecondary).frame(width: 32, height: 32)
            }
            .padding(.leading, 16).padding(.trailing, 10)
            .frame(height: 68)
            Text(description(mode))
                .font(.system(size: 14)).tracking(0.07)
                .foregroundStyle(ink.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 68).padding(.trailing, 16).padding(.bottom, 16)
        }
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(ink.bgSecondary))
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onTapGesture { home.setMode(mode) }
    }

    private func description(_ mode: SecurityMode) -> String {
        switch mode {
        case .armAway: return "Protect your home inside and out when you're away."
        case .armHome: return "Stay protected when at home with devices you choose to stay armed."
        case .standby: return "Disarm your devices and keep specific ones armed."
        }
    }
}

// MARK: - Emergency

struct NexusEmergency: View {
    let ink: NexusInk
    let size: CGSize
    @Environment(\.labNoGlass) private var noGlass

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Image("nexus-map", bundle: .module).resizable().scaledToFill()
                    .frame(width: size.width, height: 460 - NexusNavBar.height, alignment: .center)
                    .clipped()
                    .opacity(ink.dark ? 0.85 : 1)
                // The pin: the house in the file's blue gradient, the home's
                // name under it.
                VStack(spacing: 2) {
                    ZStack {
                        Circle().fill(.white).frame(width: 67, height: 67)
                            .shadow(color: .black.opacity(0.24), radius: 8, y: 4)
                        Circle().fill(LinearGradient(colors: [Color(hex: "#055E88"), Color(hex: "#012536")], startPoint: .leading, endPoint: .trailing))
                            .frame(width: 58, height: 58)
                        Image(systemName: "house.fill").font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                    }
                    Circle().fill(Color(hex: "#055E88")).frame(width: 7, height: 7)
                    Text("Smith Home").font(.system(size: 12, weight: .bold)).tracking(-0.4).foregroundStyle(Color(hex: "#055E88"))
                }
                .offset(x: -14, y: 24)
                VStack(spacing: 8) {
                    Image(systemName: "location.fill").font(.system(size: 17, weight: .semibold)).foregroundStyle(Color(hex: "#2288DD")).frame(width: 36, height: 36)
                    Image(systemName: "globe.americas.fill").font(.system(size: 19, weight: .medium)).foregroundStyle(ink.textPrimary).frame(width: 36, height: 36)
                }
                .padding(.horizontal, 6)
                .frame(height: 95)
                .modifier(NexusLightGlass(shape: Capsule(), ink: ink, noGlass: noGlass))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 12).padding(.bottom, 16)
            }
            .frame(width: size.width, height: 460 - NexusNavBar.height)
            VStack(spacing: 20) {
                Text("Emergency Response").font(.system(size: 20, weight: .semibold)).tracking(-0.45).foregroundStyle(ink.textPrimary)
                VStack(spacing: 12) {
                    VStack(spacing: 8) {
                        pill(.siren, "Activate Siren")
                        pill(.callFriend, "Call a Friend")
                    }
                    HStack(spacing: 8) {
                        card(.fire, "Fire", Color(hex: "#F8B541"))
                        card(.police, "Police", Color(hex: "#2288DD"))
                        card(.medical, "Medical", Color(hex: "#D22434"))
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 16)
            .frame(maxWidth: .infinity)
            .background(ink.bgPrimary)
            Spacer(minLength: 0)
        }
        .frame(width: size.width)
    }

    private func pill(_ glyph: NexusGlyph, _ title: String) -> some View {
        HStack(spacing: 8) {
            NexusGlyphView(glyph, color: ink.action).frame(width: 32, height: 32)
            Text(title).font(.system(size: 17, weight: .semibold)).tracking(-0.43).foregroundStyle(ink.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .background(Capsule().fill(ink.bgSecondary))
    }

    private func card(_ glyph: NexusGlyph, _ title: String, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            NexusGlyphView(glyph, color: tint).frame(width: 40, height: 40)
            Text(title).font(.system(size: 17, weight: .semibold)).tracking(-0.43).foregroundStyle(ink.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 110)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(ink.bgSecondary))
    }
}

/// Glass over a light picture: the file's white-tinted regular glass.
struct NexusLightGlass<S: Shape>: ViewModifier {
    let shape: S
    let ink: NexusInk
    let noGlass: Bool
    func body(content: Content) -> some View {
        if noGlass {
            content.background(shape.fill(ink.chrome.opacity(0.9)))
        } else if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular.tint(ink.chrome.opacity(0.5)), in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}
