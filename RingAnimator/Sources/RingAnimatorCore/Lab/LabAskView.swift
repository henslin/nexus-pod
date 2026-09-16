import SwiftUI

// The Ask button — the agent everywhere in the app, not only on its tab.
//
// Chris, overnight 2026-09-15/16: "similar to Apple's OS 27s where they
// have 'Ask Siri' everywhere. I think we can/should explore the gooey
// controls for a very cool 'Ask' button app-wide."
//
// The thing that makes an assistant worth a button on every screen is
// that it already knows what screen you're on. So the button carries
// *context*: on Devices, the first suggestions are about the devices in
// front of you; the generic verbs are one tap further. That is the
// difference between "Ask Siri" and a search field.

/// How the Ask button is drawn.
public enum LabAskStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case goo, pill, orb, bar
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .goo: return "Goo"
        case .pill: return "Pill"
        case .orb: return "Orb"
        case .bar: return "Bar"
        }
    }
}

/// Screen-specific suggestions — what the button offers on Devices.
public struct LabAskContext {
    public static let devices = ["Why is the driveway camera offline?", "Which batteries are low?", "Add a device"]
    public static let generic = ["Ask a question", "Talk to Nexus", "Show me"]
}

/// The button itself, closed or open, in a phone's coordinates. Shared
/// by the Ask Button lab and Q Branch's play.
struct LabAskButton: View {
    let frame: LabFrame
    @ObservedObject var config: RingConfig
    let size: CGSize
    let placement: LabAskPlacement
    let style: LabAskStyle
    let open: Bool
    /// Seconds since it last opened or closed.
    let since: Double
    let items: [LabActionItem]
    var suggestions: [String] = []
    var label: String = "Ask"
    var buttonSize: CGFloat = 52
    var glow: Double = 0.6

    private var primary: Color { frame.colors.first ?? .accentColor }
    private var podHome: CGPoint {
        let pod = CGFloat(RingConfig.tabBarPodDiameter)
        return CGPoint(x: LabPhone.inset + (size.width - LabPhone.inset * 2) - pod / 2, y: size.height - LabPhone.bottom - pod / 2)
    }
    /// Where the button sits, by placement.
    private var home: CGPoint {
        let r = buttonSize / 2
        switch placement {
        case .floating: return CGPoint(x: size.width - 16 - r, y: size.height - LabPhone.bottom - 62 - 14 - r)
        case .navBar: return CGPoint(x: size.width - 16 - 22, y: 62)
        case .tabBar: return podHome
        }
    }
    private var fillChoice: Int { Int(frame.p("fill", .gooey)) }
    private var fill: Color {
        switch fillChoice {
        case 1: return Color(white: 0.92)
        case 2: return Color(hex: "#5AC8FA")
        case 3: return Color(hex: "#FFCF9E")
        case 4: return primary
        default: return Color(white: 0.13)
        }
    }
    private var ink: Color { fillChoice == 0 ? .white : Color(white: 0.1) }

    var body: some View {
        let p = min(1, since / 0.35)
        let eased = open ? 1 - pow(1 - p, 3) : pow(1 - p, 3)
        // In the pod, the pod is the button: a pill or a bar there would
        // be a second thing in the same slot.
        let style: LabAskStyle = placement == .tabBar ? (self.style == .orb ? .orb : .goo) : self.style
        ZStack {
            switch style {
            case .goo, .orb:
                // The goo's menu comes out of the button; the orb wears
                // the hero instead of the goo's disc.
                LabGooeyMenu(frame: frame, center: home, open: open, since: since,
                             icons: items.map(\.symbol), drawsButton: style == .goo && placement != .tabBar)
                if style == .orb, placement != .tabBar {
                    LabHeroView(frame: frame, config: config, diameter: buttonSize)
                        .shadow(color: primary.opacity(glow * 0.6), radius: 14)
                        .position(home)
                } else if style == .goo, placement != .tabBar {
                    Image(systemName: "sparkles")
                        .font(.system(size: buttonSize * 0.4, weight: .semibold))
                        .foregroundStyle(ink)
                        .opacity(1 - eased)
                        .position(home)
                }
                if !suggestions.isEmpty {
                    suggestionStack(anchor: home, up: placement != .navBar, eased: eased)
                }
            case .pill:
                // A glass pill with the mark and a word; it opens into a
                // panel of suggestions and a field, above itself.
                let w: CGFloat = open ? size.width - LabPhone.inset * 2 : buttonSize * 1.9
                let h: CGFloat = open ? 206 : buttonSize * 0.85
                let center = placement == .navBar
                    ? CGPoint(x: open ? size.width / 2 : home.x - w / 2 + 22, y: open ? 62 + h / 2 - 20 : home.y)
                    : CGPoint(x: open ? size.width / 2 : home.x - w / 2 + buttonSize / 2, y: open ? home.y - h / 2 + buttonSize * 0.45 : home.y)
                ZStack {
                    if open {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                LabHeroView(frame: frame, config: config, diameter: 30)
                                Text("Ask Nexus").font(.headline)
                                Spacer(minLength: 0)
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                            }
                            LabWrap(spacing: 6) {
                                ForEach(Array(suggestions.enumerated()), id: \.offset) { i, s in
                                    Text(s)
                                        .font(.system(size: 13, weight: .medium))
                                        .padding(.horizontal, 11).padding(.vertical, 7)
                                        .background(Capsule().fill(.fill.tertiary))
                                        .overlay(Capsule().strokeBorder(primary.opacity(0.35)))
                                        .opacity(min(1, max(0, (since - Double(i) * 0.06 - 0.15) * 5)))
                                }
                            }
                            HStack {
                                Text("Or type…").foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                                Image(systemName: "mic.fill").foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 14).frame(height: 40)
                            .background(Capsule().fill(.fill.tertiary))
                        }
                        .padding(16)
                        .opacity(eased)
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles").font(.system(size: 14, weight: .semibold))
                            Text(label).font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(.primary)
                    }
                }
                .frame(width: w, height: h)
                .modifier(LabGlassShape(cornerRadius: open ? 26 : h / 2, glass: config.glass))
                .shadow(color: primary.opacity(glow * 0.35), radius: 16)
                .position(center)
                .animation(.spring(response: 0.45, dampingFraction: 0.82), value: open)
            case .bar:
                // A field above the tab bar — "Ask about this screen…" —
                // whose suggestions rise when it's focused.
                let barY = size.height - LabPhone.bottom - 62 - 12 - 22
                VStack(spacing: 8) {
                    if open {
                        LabWrap(spacing: 6, alignment: .trailing) {
                            ForEach(Array(suggestions.enumerated()), id: \.offset) { i, s in
                                Text(s)
                                    .font(.system(size: 13, weight: .medium))
                                    .padding(.horizontal, 11).padding(.vertical, 7)
                                    .modifier(LabGlassShape(cornerRadius: 16, glass: config.glass))
                                    .opacity(min(1, max(0, (since - Double(i) * 0.07) * 5)))
                                    .offset(y: CGFloat(1 - min(1, max(0, (since - Double(i) * 0.07) * 5))) * 10)
                            }
                        }
                        .frame(width: size.width - LabPhone.inset * 2)
                    }
                    HStack(spacing: 10) {
                        LabHeroView(frame: frame, config: config, diameter: 28)
                        Text(open ? "Ask about Devices…" : "Ask Nexus about this screen")
                            .font(.subheadline)
                            .foregroundStyle(open ? .primary : .secondary)
                            .contentTransition(.numericText())
                        Spacer(minLength: 0)
                        Image(systemName: "mic.fill").foregroundStyle(.secondary).font(.subheadline)
                    }
                    .padding(.horizontal, 14)
                    .frame(width: size.width - LabPhone.inset * 2, height: 44)
                    .modifier(LabGlassShape(cornerRadius: 22, glass: config.glass))
                    .shadow(color: primary.opacity(open ? glow * 0.4 : 0), radius: 14)
                }
                .position(x: size.width / 2, y: barY)
                .offset(y: open ? -CGFloat(min(suggestions.count, 3)) * 12 : 0)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: open)
            }
        }
    }

    /// Suggestions as glass chips, stacked away from the button and
    /// staggered in — for the goo and the orb, which have no panel.
    private func suggestionStack(anchor: CGPoint, up: Bool, eased: Double) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            ForEach(Array(suggestions.enumerated()), id: \.offset) { i, s in
                let t = min(1, max(0, (since - Double(i) * 0.07 - 0.1) * 5))
                let a = open ? t : max(0, 1 - since * 4)
                Text(s)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 11).padding(.vertical, 7)
                    .modifier(LabGlassShape(cornerRadius: 16, glass: config.glass))
                    .opacity(a)
                    .offset(x: CGFloat(1 - a) * 12)
            }
        }
        .frame(width: size.width - LabPhone.inset * 2, alignment: .trailing)
        .position(x: size.width / 2, y: up ? anchor.y - buttonSize / 2 - 14 - CGFloat(suggestions.count) * 17 : anchor.y + 30 + CGFloat(suggestions.count) * 17)
        .allowsHitTesting(false)
    }
}

// MARK: - The lab

/// Controls · Ask Button: the Ask button on the Devices screen, in every
/// placement and style, with what it offers when tapped.
struct LabAskButtonView: View {
    let frame: LabFrame
    @ObservedObject var config: RingConfig

    var body: some View {
        let placement = LabAskPlacement.allCases[min(2, Int(frame.p("placement", .askButton)))]
        let style = LabAskStyle.allCases[min(3, Int(frame.p("style", .askButton)))]
        let context = frame.p("context", .askButton) >= 0.5
        let labelChoice = Int(frame.p("label", .askButton))
        let auto = frame.p("auto", .askButton) >= 0.5
        let autoOpen = auto && Int(frame.time / 3.5) % 2 == 1
        let open = (frame.taps % 2 == 1) != autoOpen
        let since = min(frame.sinceTap, auto ? frame.time.truncatingRemainder(dividingBy: 3.5) : .infinity)
        let suggestions = context ? LabAskContext.devices : (style == .goo || style == .orb ? [] : LabAskContext.generic)
        LabPhoneCanvas(frame: frame) { size in
            ZStack {
                LabPhoneBackdrop(frame: frame, tab: .devices, size: size)
                Color.black.opacity(open ? 0.25 : 0)
                    .animation(.easeOut(duration: 0.3), value: open)
                VStack {
                    Spacer()
                    TabBarPreview(config: config, selectedTab: .constant(.devices), width: size.width - LabPhone.inset * 2, hidesPodContent: true)
                        .allowsHitTesting(false)
                        .padding(.bottom, LabPhone.bottom)
                }
                // The pod keeps the hero; the button is the second way in.
                let pod = CGFloat(RingConfig.tabBarPodDiameter)
                LabHeroView(frame: frame, config: config, diameter: pod)
                    .position(x: LabPhone.inset + (size.width - LabPhone.inset * 2) - pod / 2, y: size.height - LabPhone.bottom - pod / 2)
                    .opacity(placement == .tabBar && style != .orb && style != .goo ? 1 : (placement == .tabBar ? 0 : 1))
                LabAskButton(frame: frame, config: config, size: size, placement: placement, style: style,
                             open: open, since: since, items: [.ask, .talk, .show],
                             suggestions: suggestions,
                             label: ["Ask", "Ask Nexus", "Nexus"][min(2, labelChoice)],
                             buttonSize: frame.p("size", .askButton),
                             glow: frame.p("glow", .askButton))
                VStack {
                    Spacer()
                    Text(open ? "Tap to close" : "Tap to ask")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.bottom, 100)
                }
            }
        }
    }
}
