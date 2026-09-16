import SwiftUI

// Quidgets — quick widgets, in the agent's replies.
//
// Chris, 2026-09-16: "They're widgets that can be rendered in 3 different
// sizes. When small, there can be up to 3 next to each other. They're
// part of the responses the agent can respond with. Say you ask to turn
// your lights to 20%. We do that. Then render a quidget inline… if 20%
// is too dim, you tap on the quidget, have it expand, quickly make your
// changes, tap off of it and have it go back into place. This solves for
// not having to ask over and over again to get settings right."
//
// Built to his designs, in points on a 402-wide screen: the chat ground,
// the bubble, the reply, the quidget at 130 × 140 (small) or 370 wide
// (medium), and its expanded form over a dim. Liquid Glass for the
// containers; the controls are usable (they move a demo state, not a
// device).

// MARK: - Model

/// A quidget's kind, with the demo state it controls.
public enum QuidgetKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case light, security, clip
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .light: return "Light"
        case .security: return "Security"
        case .clip: return "Clip"
        }
    }
}

public enum QuidgetSize: String, CaseIterable, Identifiable, Sendable {
    case small, medium, large
    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }
}

/// The house's modes, as the security quidget shows them.
public enum SecurityMode: String, CaseIterable, Identifiable, Sendable {
    case armAway, armHome, standby
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .armAway: return "Arm Away"
        case .armHome: return "Arm Home"
        case .standby: return "Standby"
        }
    }
    public var symbol: String {
        switch self {
        case .armAway: return "house.fill"
        case .armHome: return "figure.stand"
        case .standby: return "house.slash"
        }
    }
}

/// What the quidgets control, for the demo: one light, one house mode.
/// `expanded` is which quidget is open over the dim, if any.
@MainActor
public final class QuidgetDemo: ObservableObject {
    @Published public var lightLevel: Double = 0.4
    @Published public var mode: SecurityMode = .armAway
    @Published public var expanded: QuidgetKind? = nil
    public init() {}
}

// MARK: - Palette, from the designs

enum QuidgetInk {
    static let ground = Color(red: 0.949, green: 0.949, blue: 0.969)        // the chat
    static let panel = Color(red: 0.937, green: 0.937, blue: 0.949)         // expanded card
    static let well = Color(red: 0.871, green: 0.871, blue: 0.890)          // the security tray
    static let track = Color(red: 0.804, green: 0.804, blue: 0.824)         // the dimmer's track
    static let amber = Color(red: 0.965, green: 0.722, blue: 0.290)         // the dimmer's fill
    static let amberKnob = Color(red: 0.973, green: 0.800, blue: 0.470)
    static let amberEdge = Color(red: 0.878, green: 0.639, blue: 0.227)
    static let amberInk = Color(red: 0.788, green: 0.510, blue: 0.165)
    static let red = Color(red: 0.878, green: 0.157, blue: 0.165)
    static let redDeep = Color(red: 0.760, green: 0.090, blue: 0.110)
    static let grey = Color(red: 0.557, green: 0.557, blue: 0.576)
    static let label = Color(red: 0.431, green: 0.431, blue: 0.451)
    static let green = Color(red: 0.118, green: 0.725, blue: 0.333)
    static let blue = Color(red: 0.102, green: 0.451, blue: 0.910)
}

/// The glass a quidget's container wears: a light glass with a soft
/// white rim, as drawn. Flat in harnesses.
struct QuidgetGlass: ViewModifier {
    let radius: CGFloat
    var tint: Color? = nil
    var rim: Double = 0.9
    var shadow = true
    @Environment(\.labNoGlass) private var noGlass

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Group {
            if noGlass {
                content.background(shape.fill(tint ?? Color.white.opacity(0.7)))
            } else if #available(iOS 26.0, macOS 26.0, *) {
                content.glassEffect(tint.map { Glass.regular.tint($0) } ?? .regular, in: shape)
            } else {
                content.background(.regularMaterial, in: shape)
            }
        }
        .overlay(shape.strokeBorder(Color.white.opacity(rim), lineWidth: rim > 0.5 ? 2 : 1))
        .shadow(color: .black.opacity(shadow ? 0.10 : 0), radius: 14, y: 6)
    }
}

// MARK: - The quidget

/// One quidget, at a size. Small and medium tap to expand; large is the
/// expanded form, used by `QuidgetOverlay`.
public struct QuidgetView: View {
    public let kind: QuidgetKind
    public let size: QuidgetSize
    @ObservedObject var demo: QuidgetDemo
    var namespace: Namespace.ID? = nil

    public init(kind: QuidgetKind, size: QuidgetSize, demo: QuidgetDemo, namespace: Namespace.ID? = nil) {
        self.kind = kind
        self.size = size
        self.demo = demo
        self.namespace = namespace
    }

    public static let smallSize = CGSize(width: 130, height: 140)
    public static let mediumWidth: CGFloat = 370

    public var body: some View {
        Group {
            switch kind {
            case .light: light
            case .security: security
            case .clip: clip
            }
        }
        .matched(kind, namespace)
    }

    // MARK: Light

    @ViewBuilder
    private var light: some View {
        switch size {
        case .small:
            QuidgetDimmer(level: $demo.lightLevel, track: CGSize(width: 102, height: 118), knob: CGSize(width: 94, height: 46), radius: 20, icon: 15)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .frame(width: Self.smallSize.width, height: Self.smallSize.height)
                .modifier(QuidgetGlass(radius: 26))
                .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .onTapGesture { expand() }
        case .medium:
            HStack(spacing: 18) {
                QuidgetDimmer(level: $demo.lightLevel, track: CGSize(width: 102, height: 118), knob: CGSize(width: 94, height: 46), radius: 20, icon: 15)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Patio Light").font(.system(size: 17, weight: .semibold))
                    Text("\(Int((demo.lightLevel * 100).rounded()))%").font(.system(size: 17))
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .frame(width: Self.mediumWidth, height: Self.smallSize.height)
            .modifier(QuidgetGlass(radius: 26))
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .onTapGesture { expand() }
        case .large:
            VStack(spacing: 0) {
                Text("Patio Light").font(.system(size: 17, weight: .semibold)).padding(.top, 36)
                Text("\(Int((demo.lightLevel * 100).rounded()))%").font(.system(size: 17))
                    .contentTransition(.numericText())
                    .padding(.top, 2)
                QuidgetDimmer(level: $demo.lightLevel, track: CGSize(width: 154, height: 378), knob: CGSize(width: 140, height: 60), radius: 24, icon: 22)
                    .padding(.top, 26)
                Spacer(minLength: 0)
            }
            .frame(width: Self.mediumWidth, height: 520)
            .modifier(QuidgetGlass(radius: 28, tint: QuidgetInk.panel))
        }
    }

    // MARK: Security

    @ViewBuilder
    private var security: some View {
        switch size {
        case .small:
            VStack(spacing: 10) {
                modeButton(demo.mode, selected: true)
                Text(demo.mode.label).font(.system(size: 12, weight: .semibold)).foregroundStyle(QuidgetInk.label)
            }
            .frame(width: 110, height: 120)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(QuidgetInk.well))
            .padding(10)
            .frame(width: Self.smallSize.width, height: Self.smallSize.height)
            .modifier(QuidgetGlass(radius: 26))
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .onTapGesture { expand() }
        case .medium:
            modeTray
                .padding(10)
                .frame(width: Self.mediumWidth, height: 162)
                .modifier(QuidgetGlass(radius: 28))
                .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .onTapGesture { expand() }
        case .large:
            VStack(spacing: 0) {
                modeTray
                    .padding(10)
                VStack(spacing: 0) {
                    statusRow(symbol: "house.fill", title: demo.mode.label, status: demo.mode == .standby ? "Off" : "Active")
                    Divider().padding(.leading, 60)
                    statusRow(symbol: "shield.lefthalf.filled", title: "Automated Threat Response", status: demo.mode == .standby ? "Paused" : "Monitoring")
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
            .frame(width: Self.mediumWidth)
            .modifier(QuidgetGlass(radius: 28, tint: QuidgetInk.panel))
        }
    }

    /// The three modes, as round buttons in a grey tray.
    private var modeTray: some View {
        HStack(spacing: 0) {
            ForEach(SecurityMode.allCases) { mode in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { demo.mode = mode }
                } label: {
                    VStack(spacing: 14) {
                        modeButton(mode, selected: demo.mode == mode)
                        Text(mode.label).font(.system(size: 12, weight: .semibold)).foregroundStyle(QuidgetInk.label)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 18)
        .frame(height: 142)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(QuidgetInk.well))
    }

    private func modeButton(_ mode: SecurityMode, selected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(selected && mode == .armAway
                      ? AnyShapeStyle(LinearGradient(colors: [QuidgetInk.red, QuidgetInk.redDeep], startPoint: .top, endPoint: .bottom))
                      : AnyShapeStyle(Color.white))
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
            Image(systemName: mode.symbol)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(selected && mode == .armAway ? Color.white : QuidgetInk.grey)
        }
        .frame(width: 62, height: 62)
        .overlay(Circle().strokeBorder(Color.white.opacity(selected && mode != .armAway ? 0 : 0), lineWidth: 2))
        .scaleEffect(selected ? 1 : 0.96)
    }

    private func statusRow(symbol: String, title: String, status: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(QuidgetInk.grey)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(.black)
                Text(status).font(.system(size: 15)).foregroundStyle(QuidgetInk.green)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 62)
    }

    // MARK: Clip

    @ViewBuilder
    private var clip: some View {
        switch size {
        case .small:
            clipImage(size: Self.smallSize, radius: 26, caption: false)
                .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .onTapGesture { expand() }
        case .medium:
            clipImage(size: CGSize(width: Self.mediumWidth, height: 362), radius: 22, caption: true)
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .onTapGesture { expand() }
        case .large:
            clipImage(size: CGSize(width: Self.mediumWidth, height: 380), radius: 22, caption: true)
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.95), lineWidth: 3))
        }
    }

    private func clipImage(size: CGSize, radius: CGFloat, caption: Bool) -> some View {
        ZStack(alignment: .bottom) {
            Image("porch-clip", bundle: .module)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
            if caption {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Amazon package was delivered").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    Text("Front Door | 2:15pm").font(.system(size: 13)).foregroundStyle(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .modifier(QuidgetGlass(radius: 12, tint: Color.black.opacity(0.18), rim: 0.35, shadow: false))
                .padding(10)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 14, y: 6)
    }

    private func expand() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { demo.expanded = kind }
    }
}

private extension View {
    @ViewBuilder
    func matched(_ kind: QuidgetKind, _ ns: Namespace.ID?) -> some View {
        if let ns { self.matchedGeometryEffect(id: kind.rawValue, in: ns) } else { self }
    }
}

// MARK: - The dimmer

/// The light's control: a rounded track, amber from the bottom up to the
/// level, and a capsule knob carrying the bulb. Drag anywhere on it.
struct QuidgetDimmer: View {
    @Binding var level: Double
    let track: CGSize
    let knob: CGSize
    let radius: CGFloat
    let icon: CGFloat

    var body: some View {
        let fillH = max(knob.height / 2, CGFloat(level) * track.height)
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(QuidgetInk.track)
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(QuidgetInk.amber)
                .frame(height: fillH)
            // The knob rides the fill's top edge: a Liquid Glass squircle
            // carrying the bulb (Chris: "the slider grabbers are liquid
            // glass squircles with SF Symbols within").
            QuidgetKnob(radius: min(radius, knob.height / 2 - 2), tint: QuidgetInk.amberKnob) {
                Image(systemName: "lightbulb.fill").font(.system(size: icon, weight: .semibold)).foregroundStyle(QuidgetInk.amberInk)
            }
            .frame(width: knob.width, height: knob.height)
            .padding(.bottom, min(track.height - knob.height, max(0, fillH - knob.height / 2)))
        }
        .frame(width: track.width, height: track.height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { g in
                let v = 1 - Double(g.location.y / track.height)
                withAnimation(.interactiveSpring()) { level = min(1, max(0, v)) }
            })
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: level)
    }
}

/// A slider's grabber: a glass squircle with a glyph in it.
struct QuidgetKnob<Glyph: View>: View {
    let radius: CGFloat
    let tint: Color
    @ViewBuilder let glyph: () -> Glyph
    @Environment(\.labNoGlass) private var noGlass

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Group {
            if noGlass {
                glyph().frame(maxWidth: .infinity, maxHeight: .infinity).background(shape.fill(tint))
            } else if #available(iOS 26.0, macOS 26.0, *) {
                glyph().frame(maxWidth: .infinity, maxHeight: .infinity).glassEffect(.regular.tint(tint.opacity(0.7)).interactive(), in: shape)
            } else {
                glyph().frame(maxWidth: .infinity, maxHeight: .infinity).background(.thinMaterial, in: shape)
            }
        }
        .overlay(shape.strokeBorder(Color.white.opacity(0.55), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }
}

// MARK: - The chat, and the overlay

/// One exchange as designed: the ask as a bubble on the right, the
/// reply, the quidget inline, and — for some — the follow-up chips.
public struct QuidgetExchange: Identifiable, Sendable {
    public var id: String
    public var ask: String
    public var reply: String
    public var kind: QuidgetKind
    public var chips: [String]

    public static let all: [QuidgetExchange] = [
        QuidgetExchange(id: "light", ask: "Dim the Patio Light", reply: "I’ve dimmed the lights to 40%.", kind: .light, chips: []),
        QuidgetExchange(id: "security", ask: "Arm my system", reply: "Your cameras are armed and your system is in Arm Away mode.", kind: .security, chips: ["Arm Away when you leave?", "Disarm when you arrive home?"]),
        QuidgetExchange(id: "clip", ask: "Did I receive any packages today?", reply: "You received a package from Amazon at 2:15PM.", kind: .clip, chips: []),
    ]
}

/// The chat screen from the designs, with the quidgets live: tap one to
/// expand it over a dim; tap the dim to put it back.
public struct QuidgetChatView: View {
    @ObservedObject var demo: QuidgetDemo
    let exchanges: [QuidgetExchange]
    let size: QuidgetSize
    let screen: CGSize
    @Namespace private var ns

    public init(demo: QuidgetDemo, exchanges: [QuidgetExchange], size: QuidgetSize = .small, screen: CGSize) {
        self.demo = demo
        self.exchanges = exchanges
        self.size = size
        self.screen = screen
    }

    public var body: some View {
        ZStack(alignment: .top) {
            QuidgetInk.ground
            VStack(alignment: .leading, spacing: 0) {
                ForEach(exchanges) { x in
                    exchange(x)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 132)
            .padding(.horizontal, 16)
            .frame(width: screen.width, height: screen.height, alignment: .top)
            // Full-screen modal: the chat blurs behind the expanded quidget.
            .blur(radius: demo.expanded == nil ? 0 : 16)
            .animation(.easeInOut(duration: 0.3), value: demo.expanded == nil)
            QuidgetOverlay(demo: demo, namespace: ns, screen: screen)
        }
        .frame(width: screen.width, height: screen.height)
        .environment(\.colorScheme, .light)
    }

    private func exchange(_ x: QuidgetExchange) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer(minLength: 40)
                Text(x.ask)
                    .font(.system(size: 17))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(Color.white))
            }
            Text(x.reply)
                .font(.system(size: 17))
                .foregroundStyle(.black)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 40)
            // The quidget's place stays while it's expanded — it comes
            // back here.
            ZStack(alignment: .leading) {
                let inline = x.kind == .clip && size == .small ? QuidgetSize.medium : size
                let h: CGFloat = inline == .small ? QuidgetView.smallSize.height : (x.kind == .clip ? 362 : x.kind == .security ? 162 : QuidgetView.smallSize.height)
                Color.clear.frame(height: h)
                if demo.expanded != x.kind {
                    QuidgetView(kind: x.kind, size: inline, demo: demo, namespace: ns)
                }
            }
            .padding(.top, 12)
            if !x.chips.isEmpty {
                HStack(spacing: 8) {
                    ForEach(x.chips, id: \.self) { chip in
                        HStack(spacing: 5) {
                            Image(systemName: "sparkles").font(.system(size: 11, weight: .semibold))
                            Text(chip).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        }
                        .fixedSize()
                        .foregroundStyle(QuidgetInk.blue)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Capsule().fill(Color.white))
                    }
                }
                .padding(.top, 44)
            }
        }
        .padding(.bottom, 28)
    }
}

/// The expanded quidget over a dim of the screen. Tap the dim to put it
/// back; the geometry matches, so it grows out of its inline place.
public struct QuidgetOverlay: View {
    @ObservedObject var demo: QuidgetDemo
    let namespace: Namespace.ID
    let screen: CGSize

    public init(demo: QuidgetDemo, namespace: Namespace.ID, screen: CGSize) {
        self.demo = demo
        self.namespace = namespace
        self.screen = screen
    }

    public var body: some View {
        ZStack(alignment: .top) {
            if let kind = demo.expanded {
                Color.black.opacity(0.32)
                    .frame(width: screen.width, height: screen.height)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { demo.expanded = nil }
                    }
                    .transition(.opacity)
                QuidgetView(kind: kind, size: .large, demo: demo, namespace: namespace)
                    .padding(.top, 120)
            }
        }
        .frame(width: screen.width, height: screen.height, alignment: .top)
        .allowsHitTesting(demo.expanded != nil)
    }
}


// MARK: - The lab

/// Containers · Quidgets: the chat from the designs, with the quidgets
/// live. Tap one to expand it; change the thing; tap the dim.
struct LabQuidgetsView: View {
    let frame: LabFrame
    @StateObject private var demo = QuidgetDemo()

    var body: some View {
        let scene = Int(frame.p("scene", .quidgets))
        let size: QuidgetSize = frame.p("size", .quidgets) >= 0.5 ? .medium : .small
        let exchanges = scene >= 3 ? QuidgetExchange.all : [QuidgetExchange.all[min(2, scene)]]
        LabPhoneCanvas(frame: frame) { screen in
            QuidgetChatView(demo: demo, exchanges: exchanges, size: size, screen: screen)
        }
    }
}
