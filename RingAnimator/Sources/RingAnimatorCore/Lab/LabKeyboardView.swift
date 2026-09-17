import SwiftUI

// The iPhone keyboard, typing by itself.
//
// Chris, 2026-09-17: "an iOS 27 keyboard that can 'self-tap' when
// messages are being simulated TO the AI agent. For demo purposes."
//
// It's a picture of the keyboard, not a keyboard: a pure function of
// the ask and how much of it has been typed, on the Lab's clock, so
// every frame is deterministic and an export shows the same taps. The
// key for the character that just landed is down for most of its slot,
// with the character's pop above it; shift is lit for a capital on its
// way; the bar above predicts the ask's next words.

/// The keyboard, mid-ask.
struct LabKeyboardView: View {
    /// The whole ask, and how many characters of it are typed.
    let text: String
    let typed: Int
    /// Where in the current character's slot the clock is, 0…1.
    let phase: Double
    let width: CGFloat
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    static let rows: [[String]] = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["z", "x", "c", "v", "b", "n", "m"],
    ]
    /// The iPhone's measures: keys 42 tall on a 6 gap, rows 12 apart.
    static let keyHeight: CGFloat = 42
    static let gap: CGFloat = 6
    static let rowGap: CGFloat = 12
    static let sideInset: CGFloat = 3
    static let barHeight: CGFloat = 44
    /// The keyboard's whole height, with the predictive bar.
    static var height: CGFloat { barHeight + 8 + keyHeight * 4 + rowGap * 3 + 8 + 21 }

    /// The character down right now, if the clock is in its slot.
    private var down: Character? {
        guard typed > 0, typed <= text.count, phase < 0.7 else { return nil }
        return text[text.index(text.startIndex, offsetBy: typed - 1)]
    }
    /// The character coming next — shift lights for a capital.
    private var next: Character? {
        guard typed < text.count else { return nil }
        return text[text.index(text.startIndex, offsetBy: typed)]
    }
    private var shifted: Bool {
        if let d = down, d.isUppercase { return true }
        if let n = next, n.isUppercase { return true }
        return typed == 0
    }

    private var keyWidth: CGFloat { (width - Self.sideInset * 2 - Self.gap * 9) / 10 }

    var body: some View {
        VStack(spacing: 0) {
            predictions
                .frame(height: Self.barHeight)
            VStack(spacing: Self.rowGap) {
                row(Self.rows[0])
                row(Self.rows[1])
                HStack(spacing: Self.gap) {
                    special(width: keyWidth * 1.25 + Self.gap * 0.5, lit: shifted, down: false) {
                        Image(systemName: shifted ? "shift.fill" : "shift")
                    }
                    Spacer(minLength: 0)
                    row(Self.rows[2])
                    Spacer(minLength: 0)
                    special(width: keyWidth * 1.25 + Self.gap * 0.5, down: false) {
                        Image(systemName: "delete.left")
                    }
                }
                HStack(spacing: Self.gap) {
                    special(width: keyWidth * 1.25 + Self.gap * 0.5, down: down.map { !$0.isLetter && $0 != " " } ?? false) {
                        Text("123").font(.system(size: 16))
                    }
                    special(width: keyWidth * 1.25 + Self.gap * 0.5, down: false) {
                        Image(systemName: "face.smiling")
                    }
                    key(label: "space", size: 16, down: down == " ", wide: true)
                    special(width: keyWidth * 2.5 + Self.gap * 1.5, down: false) {
                        Text("return").font(.system(size: 16))
                    }
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, Self.sideInset)
            Spacer(minLength: 0)
        }
        .frame(width: width, height: Self.height)
        .background(dark ? Color(white: 0.11) : Color(hex: "#D1D3D9"))
    }

    /// The bar above the keys: the ask's next word, and the two after.
    private var predictions: some View {
        let words = text.split(separator: " ").map(String.init)
        let typedWords = String(text.prefix(typed)).split(separator: " ", omittingEmptySubsequences: false).count
        let upcoming = Array(words.dropFirst(max(0, typedWords - 1)).prefix(3))
        return HStack(spacing: 0) {
            ForEach(Array(upcoming.enumerated()), id: \.offset) { i, w in
                if i > 0 { Rectangle().fill(dark ? Color.white.opacity(0.15) : Color.black.opacity(0.12)).frame(width: 1, height: 24) }
                Text(i == 0 && typedWords > 0 ? "“\(w)”" : w)
                    .font(.system(size: 17))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4)
        .foregroundStyle(dark ? .white : .black)
    }

    private func row(_ keys: [String]) -> some View {
        HStack(spacing: Self.gap) {
            ForEach(keys, id: \.self) { k in
                key(label: shifted ? k.uppercased() : k, size: 23, down: down.map { $0.lowercased() == k } ?? false)
                    .frame(width: keyWidth)
            }
        }
    }

    /// A letter key: white glass, its character, and — down — the pop
    /// above it.
    private func key(label: String, size: CGFloat, down: Bool, wide: Bool = false) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(down && !wide ? (dark ? Color(white: 0.42) : Color.white) : (dark ? Color(white: 0.36) : Color.white))
                .opacity(down && wide ? 0.6 : 1)
                .shadow(color: .black.opacity(dark ? 0.5 : 0.3), radius: 0, y: 1)
            Text(label)
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(dark ? .white : .black)
        }
        .frame(height: Self.keyHeight)
        .frame(maxWidth: wide ? .infinity : nil)
        .overlay(alignment: .top) {
            if down, !wide {
                // The pop: the character, large, on a bubble rising from
                // the key.
                Text(label)
                    .font(.system(size: 36))
                    .foregroundStyle(dark ? .white : .black)
                    .frame(width: keyWidth * 1.7, height: 58)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(dark ? Color(white: 0.42) : Color.white)
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 2))
                    .offset(y: -66)
                    .zIndex(2)
            }
        }
        .zIndex(down ? 1 : 0)
    }

    /// A grey key: shift, delete, 123, emoji, return.
    private func special<L: View>(width: CGFloat, lit: Bool = false, down: Bool, @ViewBuilder _ label: () -> L) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(lit ? (dark ? Color.white : Color.white) : down ? (dark ? Color(white: 0.36) : Color.white) : (dark ? Color(white: 0.24) : Color(hex: "#ABB0BA")))
                .shadow(color: .black.opacity(dark ? 0.5 : 0.3), radius: 0, y: 1)
            label()
                .font(.system(size: 18))
                .foregroundStyle(lit ? Color.black : (dark ? Color.white : Color.black))
        }
        .frame(width: width, height: Self.keyHeight)
    }
}
