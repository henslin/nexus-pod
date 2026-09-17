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
// Built from the Figma file (Nexus Neue → Quidgets: "System Modes",
// "Package Delivery", "Multi-Commands", the "Quidget - Light" family),
// in points on a 402-wide screen. Every number below is the design's:
// the small quidget is 129 × 146 with a 34 radius over a 109 × 126 well
// (24) and a 101 × 118 tile (20); the mode buttons are 64 with a 44
// glyph box; the chips are 28 tall, SF Pro Display Semibold 11 in
// #2487ff. The containers are Liquid Glass; the controls move a demo
// state, not a device.

// MARK: - Model

/// A quidget's kind, with the demo state it controls.
public enum QuidgetKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case light, security, clip, lock, thermostat
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .light: return "Light"
        case .security: return "Security"
        case .clip: return "Clip"
        case .lock: return "Lock"
        case .thermostat: return "Thermostat"
        }
    }
    public var symbol: String {
        switch self {
        case .light: return "lightbulb.fill"
        case .security: return "house.fill"
        case .clip: return "video.fill"
        case .lock: return "lock.fill"
        case .thermostat: return "thermometer.medium"
        }
    }
}

public enum QuidgetSize: String, CaseIterable, Identifiable, Sendable {
    case small, medium, large
    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }
}

/// The house's modes, as the security quidget shows them — each with
/// its own colour from the Gap UI page: red, amber, teal.
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
    /// The selected button's gradient, top to bottom.
    var gradient: [Color] {
        switch self {
        case .armAway: return [Color(hex: "#EA333A"), Color(hex: "#BB2722")]
        case .armHome: return [Color(hex: "#F7CE46"), Color(hex: "#F19E39")]
        case .standby: return [Color(hex: "#6AE5BC"), Color(hex: "#5CC9A5")]
        }
    }
    /// The selected glyph: white in light mode, the colour's own dark
    /// in dark mode.
    func glyphInk(dark: Bool) -> Color {
        guard dark else { return .white }
        switch self {
        case .armAway: return Color(hex: "#851918")
        case .armHome: return Color(hex: "#B27628")
        case .standby: return Color(hex: "#408F76")
        }
    }
}

/// What the quidgets control, for the demo. `expanded` is which quidget
/// is open over the dim, if any.
@MainActor
public final class QuidgetDemo: ObservableObject {
    @Published public var lightLevel: Double = 0.4
    @Published public var mode: SecurityMode = .armAway
    @Published public var locked: Bool = true
    @Published public var thermostat: Int = 70
    @Published public var expanded: QuidgetKind? = nil
    /// The mode being switched to, while the house takes a moment to
    /// arm or disarm — the button shows a spinner instead of its glyph.
    @Published public var arming: SecurityMode? = nil
    private var armingTask: Task<Void, Never>?
    public init() {}

    /// Switch modes the way the house would: the button spins for a
    /// couple of seconds, then the mode lands.
    public func setMode(_ mode: SecurityMode) {
        guard mode != self.mode || arming != nil else { return }
        armingTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { arming = mode }
        armingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { self.mode = mode; self.arming = nil }
        }
    }
}

// MARK: - Palette, from the file

enum QuidgetInk {
    static let ground = Color(hex: "#F2F2F6")          // the chat
    static let well = Color(hex: "#C8C8C8")            // a device quidget's well
    static let modeWell = Color(hex: "#DCDCE0")        // the modes' well
    static let tileOff = Color(hex: "#636466")         // a dark tile (locked door, light off)
    static let tileLight = Color(hex: "#F0EAE0")       // the light's tile, lit
    static let amber = Color(hex: "#D29D48")           // unlocked
    static let dimmerFill = Color(hex: "#F8B541")      // the dimmer's fill (the tall card, 2:721)
    static let amberInk = Color(hex: "#634514")
    static let green = Color(hex: "#6CB189")           // locked
    static let greenInk = Color(hex: "#174A2C")
    static let blue = Color(hex: "#69A2E8")            // the thermostat, cooling
    static let blueInk = Color(hex: "#17539C")
    static let glyphGrey = Color(hex: "#8E919E")
    static let label = Color(hex: "#636466")
    // Dark mode, from the Gap UI page (25672:5560).
    static let groundDark = Color.black
    static let modeWellDark = Color(hex: "#2C2C30")
    static let iconDark = Color(hex: "#404040")
    static let bubbleDark = Color(hex: "#2C2C30")
    static let chip = Color(hex: "#2487FF")
    static let statusGreen = Color(hex: "#1EB955")
}

/// A container's Liquid Glass. Flat in harnesses.
struct QuidgetGlass: ViewModifier {
    let radius: CGFloat
    /// The file's white-at-80% panel, or clear glass over the chat.
    var white: Double = 0
    @Environment(\.labNoGlass) private var noGlass
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Group {
            if noGlass {
                content.background(shape.fill((dark ? Color(hex: "#1C1C1E") : Color.white).opacity(max(0.7, white))))
            } else if #available(iOS 26.0, macOS 26.0, *) {
                content.glassEffect(white > 0 ? .regular.tint((dark ? Color(hex: "#1C1C1E") : Color.white).opacity(white)) : .regular, in: shape)
            } else {
                content.background(.regularMaterial, in: shape)
            }
        }
        // The file's "Shadow": a soft dark blur under the container.
        .shadow(color: .black.opacity(0.08), radius: 20, y: 8)
    }
}

/// The file's well and tile: a fill with its two inner shadows.
struct QuidgetInset: ViewModifier {
    let radius: CGFloat
    let fill: Color
    /// The tile's shadows are stronger than the well's.
    var strong = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(
                shape.fill(fill)
                    .overlay(
                        shape.stroke(Color.black.opacity(strong ? 0.16 : 0.08), lineWidth: 3)
                            .blur(radius: 4)
                            .offset(y: 1.5)
                            .mask(shape)
                    )
                    .overlay(
                        shape.stroke(Color.white.opacity(strong ? 0.6 : 0.3), lineWidth: 1)
                            .blur(radius: 1)
                            .offset(y: -0.5)
                            .mask(shape)
                    )
            )
    }
}

// MARK: - The mode glyphs (the file's own vectors)

/// A path from an SVG `d` string — M L H V C S Z, absolute and relative.
/// The mode glyphs are the design's own drawings, not SF Symbols.
struct SVGPathShape: Shape {
    let d: String
    let box: CGSize

    func path(in rect: CGRect) -> Path {
        var p = Path()
        var cur = CGPoint.zero, start = CGPoint.zero, lastC: CGPoint? = nil
        let scale = min(rect.width / box.width, rect.height / box.height)
        let ox = rect.midX - box.width * scale / 2, oy = rect.midY - box.height * scale / 2
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * scale, y: oy + y * scale) }
        let scanner = Scanner(string: d)
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: " ,\n")
        var cmd: Character = "M"
        func num() -> CGFloat? { scanner.scanDouble().map { CGFloat($0) } }
        while !scanner.isAtEnd {
            if let c = scanner.scanCharacter(), c.isLetter { cmd = c }
            let rel = cmd.isLowercase
            switch cmd.uppercased() {
            case "M":
                guard let x = num(), let y = num() else { return p }
                cur = rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y)
                start = cur; p.move(to: pt(cur.x, cur.y)); lastC = nil
                cmd = rel ? "l" : "L"
            case "L":
                guard let x = num(), let y = num() else { return p }
                cur = rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y)
                p.addLine(to: pt(cur.x, cur.y)); lastC = nil
            case "H":
                guard let x = num() else { return p }
                cur.x = rel ? cur.x + x : x
                p.addLine(to: pt(cur.x, cur.y)); lastC = nil
            case "V":
                guard let y = num() else { return p }
                cur.y = rel ? cur.y + y : y
                p.addLine(to: pt(cur.x, cur.y)); lastC = nil
            case "C":
                guard let x1 = num(), let y1 = num(), let x2 = num(), let y2 = num(), let x = num(), let y = num() else { return p }
                let o = rel ? cur : .zero
                let c1 = CGPoint(x: o.x + x1, y: o.y + y1), c2 = CGPoint(x: o.x + x2, y: o.y + y2)
                cur = CGPoint(x: o.x + x, y: o.y + y)
                p.addCurve(to: pt(cur.x, cur.y), control1: pt(c1.x, c1.y), control2: pt(c2.x, c2.y)); lastC = c2
            case "S":
                guard let x2 = num(), let y2 = num(), let x = num(), let y = num() else { return p }
                let o = rel ? cur : .zero
                let c1 = lastC.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                let c2 = CGPoint(x: o.x + x2, y: o.y + y2)
                cur = CGPoint(x: o.x + x, y: o.y + y)
                p.addCurve(to: pt(cur.x, cur.y), control1: pt(c1.x, c1.y), control2: pt(c2.x, c2.y)); lastC = c2
            case "Z":
                p.closeSubpath(); cur = start; lastC = nil
            default:
                return p
            }
        }
        return p
    }
}

enum QuidgetGlyph {
    static let armAway = SVGPathShape(d: "M26.5027 19.583C26.5027 27.3831 17.8671 30.2051 17.8671 30.2051C17.8671 30.2051 9.23147 27.3831 9.23147 19.583V13.1312C9.23147 13.1312 15.1342 13.9498 17.8671 9.36983C20.6 13.9498 26.5027 13.1312 26.5027 13.1312V19.583ZM35.75 14.6871L17.8279 0L0 14.6902L2.12049 17.4092L4.61912 15.3507V33H31.1151V15.3453L33.6378 17.4123L35.75 14.6871Z", box: CGSize(width: 35.75, height: 33))
    static let armHome = SVGPathShape(d: "M34.8781 25.117C37.0168 25.9429 38.5 27.0962 38.5 28.7246C38.5 33.9347 23.4507 34.353 19.5877 34.3741H18.9116C15.0486 34.353 0 33.9347 0 28.7246C0 27.0962 1.48173 25.9422 3.62186 25.1163V28.7819C5.10001 29.7209 10.4496 31.1365 19.2504 31.1365C28.0497 31.1365 33.3993 29.7209 34.8781 28.7819V25.117ZM21.341 13.1805C21.4349 13.1805 21.5189 13.211 21.6056 13.2329C21.6573 13.2407 21.7068 13.2513 21.7577 13.2633C21.9391 13.3078 22.1149 13.3672 22.2755 13.4733L26.5644 16.3009C27.3045 16.7888 27.5046 17.7774 27.0083 18.5078C26.6978 18.966 26.1864 19.2142 25.6657 19.2142C25.358 19.2142 25.0461 19.1272 24.7699 18.9455L22.4168 17.3941V20.4933L24.4142 28.1829L24.3783 28.1914C23.3621 28.2635 22.2762 28.3137 21.1237 28.3413L19.4935 22.0659H19.0065L17.3813 28.3208C16.2833 28.2699 15.1924 28.1737 14.1188 28.0549L16.0832 20.4933V17.3941L13.7294 18.9455C13.4532 19.1272 13.1413 19.2142 12.8336 19.2142C12.3129 19.2142 11.8015 18.966 11.491 18.5078C10.9947 17.7774 11.1948 16.7888 11.9349 16.3009L16.2245 13.4733C16.3851 13.3679 16.5601 13.3099 16.7359 13.2668C16.7947 13.2513 16.8413 13.2407 16.8908 13.2336C16.979 13.211 17.0636 13.1805 17.159 13.1805H21.341ZM19.2144 0L36.278 13.4079L34.267 15.8968L32.8462 14.7803V26.8341C31.9878 27.0929 30.9198 27.3489 29.6188 27.5766V12.2461L19.2202 4.07356L8.88101 12.2433V27.2641C7.61516 27.0229 6.52143 26.7825 5.65361 26.5732V14.7924L4.25938 15.894L2.24046 13.4107L19.2144 0ZM19.2503 7.26021C20.5334 7.26021 21.574 8.2862 21.574 9.55119C21.574 10.8169 20.5334 11.8429 19.2503 11.8429C17.9665 11.8429 16.9258 10.8169 16.9258 9.55119C16.9258 8.2862 17.9665 7.26021 19.2503 7.26021Z", box: CGSize(width: 38.5, height: 34.3741))
    static let standby = SVGPathShape(d: "M33.4826 12.8259L35.75 14.6833L33.6371 17.4079L32.1456 16.1861V33.1964H7.79746L12.1906 29.7123H28.7558V16.5748L33.4826 12.8259ZM31.6498 6.21291L33.7198 8.97079L3.45091 32.9765L1.3809 30.2178L31.6498 6.21291ZM17.8278 0L26.2049 6.86297L23.4412 9.05487L17.8338 4.46046L6.97458 13.4062V22.115L3.58484 24.8032V16.1981L2.12047 17.4052L0 14.686L17.8278 0Z", box: CGSize(width: 35.75, height: 33.1964))

    static func shape(_ mode: SecurityMode) -> SVGPathShape {
        switch mode {
        case .armAway: return armAway
        case .armHome: return armHome
        case .standby: return standby
        }
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
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    public init(kind: QuidgetKind, size: QuidgetSize, demo: QuidgetDemo, namespace: Namespace.ID? = nil) {
        self.kind = kind
        self.size = size
        self.demo = demo
        self.namespace = namespace
    }

    /// The file's small quidget: 129 × 146, radius 34.
    public static let smallSize = CGSize(width: 129, height: 146)
    /// The file's wide panel: 384, radius 34 (inset 9 on a 402 screen).
    public static let wideWidth: CGFloat = 384
    static let wellSize = CGSize(width: 109, height: 126)
    static let tileSize = CGSize(width: 101, height: 118)

    public var body: some View {
        Group {
            switch kind {
            case .light: light
            case .security: security
            case .clip: clip
            case .lock: lock
            case .thermostat: thermostat
            }
        }
        .matched(kind, namespace)
    }

    /// The small container: the well in the glass, with the tile in it.
    /// The light's dimmer *is* the well, so it skips the well's fill.
    private func small<Tile: View>(well: Bool = true, _ tile: () -> Tile) -> some View {
        tile()
            .frame(width: Self.tileSize.width, height: Self.tileSize.height)
            .padding(4)
            .frame(width: Self.wellSize.width, height: Self.wellSize.height)
            .modifier(QuidgetInset(radius: 24, fill: well ? QuidgetInk.well : .clear))
            .padding(.top, 11).padding(.bottom, 9).padding(.horizontal, 10)
            .frame(width: Self.smallSize.width, height: Self.smallSize.height)
            .modifier(QuidgetGlass(radius: 34))
            .contentShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            .onTapGesture { expand() }
    }

    // MARK: Light

    @ViewBuilder
    private var light: some View {
        switch size {
        case .small, .medium:
            // The well is the track: 109 × 126, the fill inset 4.
            small(well: false) {
                QuidgetDimmer(level: $demo.lightLevel, track: Self.wellSize, inset: 4, knobHeight: 44, icon: 16)
                    .padding(-4)
            }
        case .large:
            // The file's tall card (2:721): 384 × 527, the title 38 down,
            // the track 160 × 383 at 111, the fill inset 10, the knob 64.
            VStack(spacing: 0) {
                Text("Patio Light").font(.system(size: 17, weight: .semibold)).foregroundStyle(dark ? .white : .black).padding(.top, 38)
                Text("\(Int((demo.lightLevel * 100).rounded()))%").font(.system(size: 17)).foregroundStyle(dark ? .white : .black)
                    .contentTransition(.numericText())
                QuidgetDimmer(level: $demo.lightLevel, track: CGSize(width: 160, height: 383), inset: 10, knobHeight: 64, icon: 22)
                    .padding(.top, 30)
                Spacer(minLength: 0)
            }
            .frame(width: Self.wideWidth, height: 527)
            .modifier(QuidgetGlass(radius: 34, white: 0.8))
        }
    }

    // MARK: Lock and thermostat (the file's other small quidgets)

    private var lock: some View {
        small {
            VStack(spacing: 0) {
                Image(systemName: demo.locked ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 30, weight: .medium))
                    .frame(width: 32, height: 32)
                    .padding(.top, 6)
                Spacer(minLength: 0)
                Text("Front Door").font(.system(size: 12, weight: .semibold)).tracking(-0.43)
                Text(demo.locked ? "Locked" : "Unlocked").font(.system(size: 12)).tracking(-0.43).padding(.bottom, 12)
            }
            .foregroundStyle(demo.locked ? QuidgetInk.greenInk : QuidgetInk.amberInk)
            .frame(width: Self.tileSize.width, height: Self.tileSize.height)
            .modifier(QuidgetInset(radius: 20, fill: demo.locked ? QuidgetInk.green : QuidgetInk.amber, strong: true))
            .onTapGesture { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { demo.locked.toggle() } }
        }
    }

    private var thermostat: some View {
        small {
            VStack(spacing: 0) {
                Text("\(demo.thermostat)°").font(.system(size: 36, weight: .light)).tracking(-0.43)
                    .foregroundStyle(QuidgetInk.blueInk)
                    .padding(.top, 22)
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    Button { demo.thermostat = max(50, demo.thermostat - 1) } label: {
                        Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    Rectangle().fill(Color.white.opacity(0.25)).frame(width: 1, height: 18)
                    Button { demo.thermostat = min(90, demo.thermostat + 1) } label: {
                        Image(systemName: "chevron.up").font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .frame(width: 85, height: 32)
                .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(QuidgetInk.blueInk))
                .padding(.bottom, 8)
            }
            .frame(width: Self.tileSize.width, height: Self.tileSize.height)
            .modifier(QuidgetInset(radius: 20, fill: QuidgetInk.blue, strong: true))
        }
    }

    // MARK: Security

    @ViewBuilder
    private var security: some View {
        switch size {
        case .small:
            modeCard(demo.mode, selected: true)
                .frame(width: 103.33)
                .padding(.top, 18)
                .frame(width: Self.wellSize.width, height: Self.wellSize.height, alignment: .top)
                .modifier(QuidgetInset(radius: 24, fill: dark ? QuidgetInk.modeWellDark : QuidgetInk.modeWell))
                .padding(.top, 11).padding(.bottom, 9).padding(.horizontal, 10)
                .frame(width: Self.smallSize.width, height: Self.smallSize.height)
                .modifier(QuidgetGlass(radius: 34))
                .contentShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                .onTapGesture { expand() }
        case .medium:
            modeTray
                .padding(.top, 10).padding(.bottom, 10).padding(.horizontal, 10.5)
                .frame(width: Self.wideWidth, height: 168)
                .modifier(QuidgetGlass(radius: 34, white: 0.8))
                .contentShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                .onTapGesture { expand() }
        case .large:
            VStack(spacing: 0) {
                modeTray
                    .padding(.top, 10).padding(.horizontal, 10.5)
                VStack(spacing: 0) {
                    if let arming = demo.arming {
                        statusRow(symbol: "house.fill", title: arming.label, status: arming == .standby ? "Standing down…" : "Arming…")
                    } else {
                        statusRow(symbol: "house.fill", title: demo.mode.label, status: demo.mode == .standby ? "Off" : "Active")
                    }
                    Divider().padding(.leading, 60)
                    statusRow(symbol: "shield.lefthalf.filled", title: "Automated Threat Response", status: demo.mode == .standby ? "Paused" : "Monitoring")
                }
                .padding(.horizontal, 10.5)
                .padding(.bottom, 10)
            }
            .frame(width: Self.wideWidth)
            .modifier(QuidgetGlass(radius: 34, white: 0.8))
        }
    }

    /// The file's tray: the modes' well, 363 × 148, three 103.33 cards.
    private var modeTray: some View {
        HStack(spacing: 0) {
            ForEach(SecurityMode.allCases) { mode in
                Button {
                    demo.setMode(mode)
                } label: {
                    modeCard(mode, selected: demo.mode == mode)
                        .frame(width: 103.33)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18.5)
        .padding(.top, 30)
        .frame(width: 363, height: 148, alignment: .top)
        .modifier(QuidgetInset(radius: 24, fill: dark ? QuidgetInk.modeWellDark : QuidgetInk.modeWell))
    }

    /// Icon + label, as the file's "Card": a 64 circle with the mode's
    /// own glyph in a 44 box, the label 10 below.
    private func modeCard(_ mode: SecurityMode, selected: Bool) -> some View {
        VStack(spacing: 10) {
            ZStack {
                if selected {
                    Circle()
                        .fill(LinearGradient(colors: mode.gradient, startPoint: .top, endPoint: .bottom))
                        .overlay(Circle().stroke(Color.black.opacity(0.16), lineWidth: 2).blur(radius: 3).offset(y: 1).mask(Circle()))
                        .shadow(color: .white.opacity(0.25), radius: 0.5, y: 1)
                } else {
                    Circle()
                        .fill(dark ? QuidgetInk.iconDark : Color.white)
                        .overlay(Circle().stroke(Color.black.opacity(0.06), lineWidth: 3).blur(radius: 4).offset(y: -3).mask(Circle()))
                        .shadow(color: .black.opacity(0.16), radius: 2, y: 2)
                        .shadow(color: .black.opacity(0.08), radius: 6, y: 6)
                }
                if demo.arming == mode {
                    QuidgetSpinnerView(color: selected ? mode.glyphInk(dark: dark) : QuidgetInk.glyphGrey)
                        .frame(width: 26, height: 26)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    QuidgetGlyph.shape(mode)
                        .fill(selected ? mode.glyphInk(dark: dark) : QuidgetInk.glyphGrey)
                        .frame(width: 36, height: 36)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 64, height: 64)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: demo.arming == mode)
            Text(mode.label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(dark ? QuidgetInk.glyphGrey : QuidgetInk.label)
                .lineLimit(1)
        }
    }

    private func statusRow(symbol: String, title: String, status: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(QuidgetInk.glyphGrey)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(dark ? .white : .black)
                Text(status).font(.system(size: 15)).foregroundStyle(QuidgetInk.statusGreen)
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
            small {
                Image("porch-clip", bundle: .module)
                    .resizable().scaledToFill()
                    .frame(width: Self.tileSize.width, height: Self.tileSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        case .medium:
            cameraWidget(side: 370, radius: 26)
                .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .onTapGesture { expand() }
        case .large:
            cameraWidget(side: 370, radius: 29)
                .padding(7)
                .frame(width: Self.wideWidth, height: Self.wideWidth)
                .modifier(QuidgetGlass(radius: 34, white: 0.8))
        }
    }

    /// The file's "Camera Widget": the frame with a fade top and bottom,
    /// and the caption on glass, inset 10.
    private func cameraWidget(side: CGFloat, radius: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            Image("porch-clip", bundle: .module)
                .resizable()
                .scaledToFill()
                .frame(width: side, height: side)
                .clipped()
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom).frame(height: 116)
                Spacer(minLength: 0)
                LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom).frame(height: 116)
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Amazon package was delivered")
                        .font(.system(size: 15, weight: .semibold)).tracking(-0.23)
                        .lineLimit(1)
                    Text("Front Door | 2:15pm")
                        .font(.system(size: 11)).tracking(-0.23)
                        .frame(height: 23)
                }
                .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            .padding(.leading, 14).padding(.trailing, 17).padding(.vertical, 8)
            .frame(width: side - 20, height: 64)
            .modifier(QuidgetCaptionGlass())
            .padding(10)
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 10)
    }

    private func expand() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { demo.expanded = kind }
    }
}

/// The caption's glass: the file's white-at-7% screen over a blur, 16
/// radius.
struct QuidgetCaptionGlass: ViewModifier {
    @Environment(\.labNoGlass) private var noGlass
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        Group {
            if noGlass {
                content.background(shape.fill(Color.white.opacity(0.18)))
            } else if #available(iOS 26.0, macOS 26.0, *) {
                content.glassEffect(.regular.tint(Color.white.opacity(0.07)), in: shape)
            } else {
                content.background(.ultraThinMaterial, in: shape)
            }
        }
        .overlay(shape.strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
    }
}

private extension View {
    @ViewBuilder
    func matched(_ kind: QuidgetKind, _ ns: Namespace.ID?) -> some View {
        if let ns { self.matchedGeometryEffect(id: kind.rawValue, in: ns) } else { self }
    }
}

// MARK: - The dimmer

/// The light's tile: dark when off, the amber rising with the level, and
/// the file's glass knob — 101 × 44, radius 20, white at 20% with two
/// soft shadows — carrying the bulb. Drag anywhere.
struct QuidgetDimmer: View {
    @Binding var level: Double
    /// The track is the well: #C8C8C8, radius 24, the well's inner
    /// shadows. The fill sits inside it, inset, radius 20; the knob is
    /// the fill's width and rides its top edge.
    let track: CGSize
    let inset: CGFloat
    let knobHeight: CGFloat
    let icon: CGFloat

    var body: some View {
        let inner = CGSize(width: track.width - inset * 2, height: track.height - inset * 2)
        // At the bottom the fill is gone — the light is off, and only the
        // grabber is left (Chris, 2026-09-16). It fades over the last 8%.
        let fillH = CGFloat(level) * inner.height
        let fillAlpha = min(1, level / 0.08)
        ZStack(alignment: .bottom) {
            // The fill grows up from the bottom and darkens as the light
            // dims (Chris, 2026-09-16): the file's amber at full, a deep
            // amber near off.
            // The fill keeps its corners at both ends: tall enough for
            // two corner radii, it's a rounded rectangle of its own
            // height; shorter, it's the bottom slice of one — perfect
            // bottom corners, a straight top the grabber covers.
            DimmerFillShape(height: max(0, fillH), radius: 20)
                .fill(Self.fill(at: level))
                .overlay(DimmerFillShape(height: max(0, fillH), radius: 20)
                    .stroke(Color.black.opacity(0.16), lineWidth: 3).blur(radius: 4).offset(y: 1.5)
                    .mask(DimmerFillShape(height: max(0, fillH), radius: 20)))
                .frame(width: inner.width, height: inner.height)
                .opacity(fillAlpha)
                .padding(.bottom, inset)
            QuidgetKnob(radius: 20) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: icon, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.75))
            }
            .frame(width: inner.width, height: knobHeight)
            // The knob's top sits 7 above the fill's top on the tall card
            // (421 vs 428); the same proportion here.
            .padding(.bottom, min(track.height - inset - knobHeight, max(inset, inset + fillH - knobHeight + knobHeight * 0.11)))
            // The bulb dims with the light.
            .opacity(0.6 + 0.4 * fillAlpha)
        }
        .frame(width: track.width, height: track.height)
        .modifier(QuidgetInset(radius: 24, fill: QuidgetInk.well))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { g in
                let v = 1 - Double((g.location.y - inset) / inner.height)
                withAnimation(.interactiveSpring()) { level = min(1, max(0, v)) }
            })
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: level)
    }

    /// The file's #F8B541 at full brightness, darkening toward off.
    static func fill(at level: Double) -> Color {
        Color(hue: 0.105, saturation: 0.74 - 0.1 * level, brightness: 0.45 + 0.52 * level)
    }
}

/// The dimmer's fill: a rounded rectangle of the given height rising
/// from the bottom of its rect — or, when that would squash the
/// corners, the bottom slice of a full-radius one.
struct DimmerFillShape: Shape {
    var height: CGFloat
    let radius: CGFloat
    var animatableData: CGFloat { get { height } set { height = newValue } }

    func path(in rect: CGRect) -> Path {
        let h = min(rect.height, max(0, height))
        guard h > 0 else { return Path() }
        let band = CGRect(x: rect.minX, y: rect.maxY - h, width: rect.width, height: h)
        if h >= radius * 2 {
            return Path(roundedRect: band, cornerRadius: radius, style: .continuous)
        }
        // The bottom of a rounded rect two radii tall, cut at h.
        let tall = CGRect(x: rect.minX, y: rect.maxY - radius * 2, width: rect.width, height: radius * 2)
        return Path(roundedRect: tall, cornerRadius: radius, style: .continuous).intersection(Path(band))
    }
}

/// An indeterminate spinner: three quarters of a ring, turning once a
/// second, in the glyph's colour.
struct QuidgetSpinnerView: View {
    let color: Color
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees((t * 360).truncatingRemainder(dividingBy: 360)))
        }
    }
}

/// A slider's grabber: a glass squircle with a glyph in it. The file:
/// white at 20%, shadows 0 4 16 and 0 4 32 at 16%.
struct QuidgetKnob<Glyph: View>: View {
    let radius: CGFloat
    @ViewBuilder let glyph: () -> Glyph
    @Environment(\.labNoGlass) private var noGlass

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Group {
            if noGlass {
                glyph().frame(maxWidth: .infinity, maxHeight: .infinity).background(shape.fill(Color.white.opacity(0.35)))
            } else if #available(iOS 26.0, macOS 26.0, *) {
                glyph().frame(maxWidth: .infinity, maxHeight: .infinity).glassEffect(.regular.tint(Color.white.opacity(0.2)).interactive(), in: shape)
            } else {
                glyph().frame(maxWidth: .infinity, maxHeight: .infinity).background(.thinMaterial, in: shape)
            }
        }
        .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
        .shadow(color: .black.opacity(0.16), radius: 16, y: 4)
    }
}

// MARK: - The chat, and the overlay

/// One exchange as designed: the ask as a bubble on the right, the
/// reply, the quidgets inline (up to three small, side by side), and the
/// follow-up chips.
public struct QuidgetExchange: Identifiable, Sendable {
    public var id: String
    public var ask: String
    public var reply: String
    public var kinds: [QuidgetKind]
    public var chips: [String]

    public static let all: [QuidgetExchange] = [
        QuidgetExchange(id: "light", ask: "Dim the Patio Light", reply: "I’ve dimmed the lights to 40%.", kinds: [.light], chips: []),
        QuidgetExchange(id: "security", ask: "Arm the system in Away mode", reply: "Your cameras are armed and your system is in Arm Away mode.", kinds: [.security], chips: ["Arm Away when you leave?", "Disarm when you arrive home?"]),
        QuidgetExchange(id: "clip", ask: "Is there a package at my front door?", reply: "You received a package from Amazon at 2:15PM.", kinds: [.clip], chips: ["Notify Amazon Deliveries", "Notify of Stolen Packages"]),
        QuidgetExchange(id: "multi", ask: "Lock the front door, turn on the hallway lights, and set it to 70 degrees", reply: "Front door is locked, hallways lights are on and the thermostat is set to 70°.", kinds: [.lock, .light, .thermostat], chips: ["Create Automation", "Set as Mockupency", "Turn Lights on When I leave"]),
    ]
}

/// The chat screen from the file, with the quidgets live: tap one to
/// expand it over a blur; tap the blur to put it back.
public struct QuidgetChatView: View {
    @ObservedObject var demo: QuidgetDemo
    let exchanges: [QuidgetExchange]
    let size: QuidgetSize
    let screen: CGSize
    /// The Gap UI page's dark mode.
    var dark = false
    @Namespace private var ns
    @Environment(\.labNoGlass) private var noGlass

    public init(demo: QuidgetDemo, exchanges: [QuidgetExchange], size: QuidgetSize = .small, screen: CGSize, dark: Bool = false) {
        self.demo = demo
        self.exchanges = exchanges
        self.size = size
        self.screen = screen
        self.dark = dark
    }

    public var body: some View {
        ZStack(alignment: .top) {
            dark ? QuidgetInk.groundDark : QuidgetInk.ground
            VStack(alignment: .leading, spacing: 0) {
                ForEach(exchanges) { x in
                    exchange(x)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 125)
            .frame(width: screen.width, height: screen.height, alignment: .top)
            // Full-screen modal: the chat blurs behind the expanded quidget.
            .blur(radius: demo.expanded == nil ? 0 : 16)
            .animation(.easeInOut(duration: 0.3), value: demo.expanded == nil)
            QuidgetOverlay(demo: demo, namespace: ns, screen: screen)
        }
        .frame(width: screen.width, height: screen.height)
        .environment(\.colorScheme, dark ? .dark : .light)
    }

    private func exchange(_ x: QuidgetExchange) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // The ask: white, radius 26, 16 × 10, 27 in from the right.
            HStack {
                Spacer(minLength: 40)
                Text(x.ask)
                    .font(.system(size: 17)).tracking(-0.43)
                    .foregroundStyle(dark ? .white : .black)
                    .multilineTextAlignment(.trailing)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(dark ? QuidgetInk.bubbleDark : Color.white))
                    .frame(maxWidth: 307, alignment: .trailing)
            }
            .padding(.trailing, 27)
            Text(x.reply)
                .font(.system(size: 17)).tracking(-0.43)
                .foregroundStyle(dark ? .white : .black)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 370, alignment: .leading)
                .padding(.leading, 16)
                .padding(.top, 48)
            // The quidgets' place stays while one is expanded — it comes
            // back here. Three small sit side by side, 10 apart, and the
            // row scrolls: the file shows the third cut off at the edge.
            let row = HStack(alignment: .top, spacing: 10) {
                ForEach(x.kinds) { kind in
                    let inline = inlineSize(kind, count: x.kinds.count)
                    ZStack(alignment: .leading) {
                        Color.clear.frame(width: inlineWidth(kind, inline), height: inlineHeight(kind, inline))
                        if demo.expanded != kind {
                            QuidgetView(kind: kind, size: inline, demo: demo, namespace: ns)
                        }
                    }
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 16)
            Group {
                if noGlass {
                    row.frame(width: screen.width, alignment: .leading).clipped()
                } else {
                    ScrollView(.horizontal, showsIndicators: false) { row }
                        .frame(width: screen.width)
                }
            }
            .padding(.top, 15)
            if !x.chips.isEmpty {
                // The chips scroll too; the file runs them off the edge.
                let chips = HStack(spacing: 10) {
                    ForEach(x.chips, id: \.self) { chip in
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles.2").font(.system(size: 10, weight: .semibold))
                            Text(chip).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        }
                        .fixedSize()
                        .foregroundStyle(QuidgetInk.chip)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Capsule().fill(dark ? QuidgetInk.bubbleDark : Color.white))
                    }
                }
                .padding(.horizontal, 16)
                Group {
                    if noGlass {
                        chips.frame(width: screen.width, alignment: .leading).clipped()
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) { chips }
                            .frame(width: screen.width)
                    }
                }
                .padding(.top, 20)
            }
        }
        .padding(.bottom, 28)
    }

    private func inlineSize(_ kind: QuidgetKind, count: Int) -> QuidgetSize {
        if kind == .clip { return count > 1 ? .small : .medium }
        return count > 1 ? .small : size
    }
    private func inlineWidth(_ kind: QuidgetKind, _ s: QuidgetSize) -> CGFloat {
        s == .small ? QuidgetView.smallSize.width : (kind == .clip ? 370 : QuidgetView.wideWidth)
    }
    private func inlineHeight(_ kind: QuidgetKind, _ s: QuidgetSize) -> CGFloat {
        if s == .small { return QuidgetView.smallSize.height }
        switch kind {
        case .clip: return 370
        case .security: return 168
        default: return QuidgetView.smallSize.height
        }
    }
}

/// The expanded quidget over the blurred, dimmed screen (the file's dim:
/// black at 5% over black at 25%). Tap the dim to put it back; the
/// geometry matches, so it grows out of its inline place.
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
                Color.black.opacity(0.29)
                    .frame(width: screen.width, height: screen.height)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { demo.expanded = nil }
                    }
                    .transition(.opacity)
                QuidgetView(kind: kind, size: .large, demo: demo, namespace: namespace)
                    .padding(.top, 118)
            }
        }
        .frame(width: screen.width, height: screen.height, alignment: .top)
        .allowsHitTesting(demo.expanded != nil)
    }
}

// MARK: - The lab

/// Containers · Quidgets: the chat from the file, with the quidgets
/// live. Tap one to expand it; change the thing; tap the dim.
struct LabQuidgetsView: View {
    let frame: LabFrame
    @StateObject private var demo = QuidgetDemo()

    var body: some View {
        let scene = Int(frame.p("scene", .quidgets))
        let size: QuidgetSize = frame.p("size", .quidgets) >= 0.5 ? .medium : .small
        let exchanges = scene >= QuidgetExchange.all.count ? QuidgetExchange.all : [QuidgetExchange.all[scene]]
        LabPhoneCanvas(frame: frame) { screen in
            QuidgetChatView(demo: demo, exchanges: exchanges, size: size, screen: screen, dark: frame.darkStage)
        }
    }
}
