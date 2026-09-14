import SwiftUI

/// One entry in the merged "what does it do" list: either one of the app's
/// continuous animations or one of the firmware's fixed cue styles.
///
/// These used to be two pickers with a two-level relationship — Pattern
/// Style was "Continuous" *or* a fixed style, and only when Continuous did
/// the Type picker apply. One list is one question. The model underneath
/// is unchanged: an animation is `patternStyle == nil` plus an
/// `animationType`; a style is `patternStyle == .x`.
public enum MotionChoice: Hashable, Identifiable {
    case animation(RingAnimationType)
    case style(LEDPatternStyle)
    /// One of the shipped firmware pattern scripts, by name — the 72
    /// recorded command streams the ring replays (`spinning_rainbow`,
    /// `wifi_pairing`, …). A different kind of thing from a style: not a
    /// behaviour the app draws, but a recording of what the device does.
    /// Setting one overrides the animation entirely.
    case firmware(String)

    public var id: String {
        switch self {
        case .animation(let t): return "anim.\(t.rawValue)"
        case .style(let s):     return "style.\(s.rawValue)"
        case .firmware(let n):  return "fw.\(n)"
        }
    }

    public var name: String {
        switch self {
        case .animation(let t): return t.rawValue
        case .style(let s):     return s.displayName
        case .firmware(let n):  return Self.displayName(forPattern: n)
        }
    }

    /// `spinning_rainbow` → "Spinning Rainbow". The script name is the
    /// identity and stays as-is; this is only how it reads on a card.
    public static func displayName(forPattern name: String) -> String {
        name.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// Every shipped firmware pattern, in name order.
    public static var firmwarePatterns: [MotionChoice] {
        FirmwarePatternStream.library.keys.sorted().map(MotionChoice.firmware)
    }

    /// The fixed styles offered live. Excludes the Cue Library-only ones
    /// that don't make sense as a live override — `.earConOnly` /
    /// `.notApplicable` describe cues with no LED behaviour, `.voiceAssistantColor`
    /// defers to a platform colour this app doesn't own, `.custom` only
    /// means anything beside a cue's free-text notes. They stay selectable
    /// in the Cue Library's own picker, where they describe a spec-sheet row.
    public static var selectableStyles: [LEDPatternStyle] {
        LEDPatternStyle.allCases.filter {
            ![.continuousAnimation, .earConOnly, .notApplicable, .voiceAssistantColor, .custom].contains($0)
        }
    }

    public static var animations: [MotionChoice] { RingAnimationType.allCases.map(MotionChoice.animation) }
    public static var basicStyles: [MotionChoice] { selectableStyles.filter { !$0.isComposite }.map(MotionChoice.style) }
    public static var multiPhaseStyles: [MotionChoice] { selectableStyles.filter(\.isComposite).map(MotionChoice.style) }

    /// What the config is currently doing, as one choice. A firmware
    /// pattern wins when set, because it overrides the rest.
    public static func current(of config: RingConfig) -> MotionChoice {
        if let name = config.firmwarePatternStream { return .firmware(name) }
        return config.patternStyle.map(MotionChoice.style) ?? .animation(config.animationType)
    }

    /// Make the config do this. Choosing an animation clears any fixed
    /// style; choosing a style leaves `animationType` alone so switching
    /// back returns to the same animation. Choosing either clears a
    /// firmware pattern, since that would otherwise override them.
    public func apply(to config: RingConfig) {
        switch self {
        case .animation(let t):
            config.firmwarePatternStream = nil
            config.patternStyle = nil
            config.animationType = t
        case .style(let s):
            config.firmwarePatternStream = nil
            config.patternStyle = s
        case .firmware(let n):
            Self.applyFirmware(n, to: config)
        }
    }

    /// Exactly what `FirmwarePatternImporter` sets when it imports a
    /// pattern, because setting the name alone draws nothing: the stream
    /// only renders on the diode path, which only runs in Diode Mode. The
    /// first cut set just the name, and every firmware thumbnail showed
    /// the base animation — all 72 identical.
    static func applyFirmware(_ name: String, to config: RingConfig) {
        config.firmwarePatternStream = name
        config.firmwarePatternStreamOffset = 0
        config.diodeModeEnabled = true
        config.diodeCount = 20
        config.diodeColorMode = .perDiode
        config.diodeFloor = 0
        if let stream = FirmwarePatternStream.stream(named: name) {
            config.loopSeconds = min(max(stream.loopSeconds, 0.5), 60)
        }
    }

    /// A snapshot of `config` doing this instead — for a thumbnail.
    public func preset(from config: RingConfig) -> RingPreset {
        var p = RingPreset(name: name, config: config)
        switch self {
        case .animation(let t):
            p.firmwarePatternStream = nil
            p.patternStyle = nil
            p.animationType = t
        case .style(let s):
            p.firmwarePatternStream = nil
            p.patternStyle = s
        case .firmware(let n):
            // Through a scratch config so the preset carries the same
            // diode-mode settings `applyFirmware` sets — a thumbnail built
            // from the name alone renders the base animation instead.
            let scratch = RingConfig()
            p.apply(to: scratch)
            Self.applyFirmware(n, to: scratch)
            p = RingPreset(name: name, config: scratch)
        }
        return p
    }
}

/// The Styles section: every choice in the merged list, as a live
/// thumbnail in your current colours, so you pick a starting point by
/// looking rather than by name.
///
/// Renders each thumbnail with `AnimationThumbnail`, the same component
/// the Nexus list uses, so the gallery costs what a list of that many
/// rows costs and the previews match what selecting one will give you.
/// Picking writes straight into the live config — the Nexus animation you
/// have selected — which is why the detail pane stays the Nexus stage:
/// you see the pick land immediately.
public struct StylesGalleryView: View {
    /// What the thumbnails are rendered *from*.
    ///
    /// Two jobs, two answers (Chris, 2026-09-14). In the style well's
    /// popover you're mid-edit, so `.current` shows every style in the
    /// colours and settings you have — what it would look like with what
    /// you've got. In the Styles sidebar the gallery is a reference, so
    /// `.defaults` renders every style from a fresh config: the original
    /// intent of each, unaffected by whatever you happen to be editing.
    /// Picking applies to the live config either way.
    public enum Basis { case current, defaults }

    @ObservedObject var config: RingConfig
    let basis: Basis
    /// One fresh config for the whole gallery, not one per cell per
    /// render — `RingConfig()` is cheap but not free, and there are 98.
    private let defaults = RingConfig()

    public init(config: RingConfig, basis: Basis = .current) {
        self.config = config
        self.basis = basis
    }

    private var source: RingConfig { basis == .current ? config : defaults }

    private static let thumbnail: CGFloat = 56
    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if basis == .defaults {
                    Text("Every style at its defaults — the original intent of each, whatever you're editing. Pick one to apply it to the selected animation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                group("Animations", MotionChoice.animations,
                      "Continuous loops — the app's own.")
                group("Basic Styles", MotionChoice.basicStyles,
                      "Single spec-sheet behaviours. Sequence them on the timeline to build anything multi-phase.")
                group("Multi-phase", MotionChoice.multiPhaseStyles,
                      "Canned sequences from the Cue Library, with their own hold and fade baked in.")
                group("Firmware Patterns", MotionChoice.firmwarePatterns,
                      "The device's own scripts, replayed from their recorded command streams. These carry their own colours and override the animation entirely.")
            }
            .padding(16)
        }
        .navigationTitle("Styles")
    }

    private func group(_ title: String, _ choices: [MotionChoice], _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(caption).font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(choices) { choice in
                    cell(choice)
                }
            }
        }
    }

    private func cell(_ choice: MotionChoice) -> some View {
        let isCurrent = MotionChoice.current(of: config) == choice
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { choice.apply(to: config) }
        } label: {
            VStack(spacing: 6) {
                AnimationThumbnail(preset: choice.preset(from: source),
                                   diameter: Self.thumbnail,
                                   timelineFileName: nil)
                Text(choice.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isCurrent ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isCurrent ? Color.accentColor : .clear, lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.name)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// The Motion card's picker: a well showing the current style's live
/// thumbnail and name, which opens the gallery when clicked — Keynote's
/// transition well, Pages' paragraph-style well.
///
/// Replaces a menu, deliberately. A macOS menu item can carry a static
/// icon but not a live view, so "thumbnails in the dropdown" would have
/// been dead frames of animations. And keeping the menu *beside* the well
/// would be two controls doing the same job, which is the inconsistency
/// this panel has already been cleaned of once.
public struct StyleWell: View {
    @ObservedObject var config: RingConfig
    @State private var showingGallery = false

    public init(config: RingConfig) { self.config = config }

    public var body: some View {
        let current = MotionChoice.current(of: config)
        Button {
            showingGallery = true
        } label: {
            HStack(spacing: 10) {
                AnimationThumbnail(preset: current.preset(from: config), diameter: 28, timelineFileName: nil)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Style").font(.caption).foregroundStyle(.secondary)
                    Text(current.name).font(.system(size: 13, weight: .medium))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Style, \(current.name)")
        .popover(isPresented: $showingGallery, arrowEdge: .leading) {
            StylesGalleryView(config: config)
                .frame(width: 520, height: 560)
        }
    }
}
