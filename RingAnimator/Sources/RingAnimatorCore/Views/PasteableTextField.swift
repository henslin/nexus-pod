import SwiftUI
#if os(macOS)
import AppKit
#endif

/// A `TextField` with a "paste from clipboard" button alongside it on
/// macOS — the workaround for the text-input bug affecting this app on
/// this Xcode beta (typing/focus never reaches any TextField/SecureField
/// hosted in our own SwiftUI view hierarchy — see `Package.swift` for the
/// suspected root cause and the linker-level fix being tried for it, and
/// `SavedPresetsView` for another call site). Since typing straight into
/// the field doesn't work, the expected flow is: copy the desired text
/// somewhere else (Notes, Finder, another field), then tap this button.
///
/// Originally a private helper duplicated inside `ControlsSections.swift`'s
/// voice message field; pulled out here once `SavedPresetsView` needed the
/// exact same workaround for its Save/Rename dialogs, so both call sites
/// share one implementation instead of drifting apart.
///
/// Once the root-cause fix is confirmed (a real Xcode rebuild with typing
/// working again), every call site of this can go back to a plain
/// `TextField` and this file can be deleted.
public struct PasteableTextField: View {
    private let title: String
    @Binding private var text: String
    private let onSubmit: (() -> Void)?

    public init(_ title: String, text: Binding<String>, onSubmit: (() -> Void)? = nil) {
        self.title = title
        self._text = text
        self.onSubmit = onSubmit
    }

    public var body: some View {
        HStack {
            TextField(title, text: $text)
                #if os(macOS)
                .textFieldStyle(.roundedBorder)
                #endif
                .onSubmit { onSubmit?() }
            #if os(macOS)
            Button {
                pasteFromClipboard()
            } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .help("Paste from clipboard")
            #endif
        }
    }

    #if os(macOS)
    private func pasteFromClipboard() {
        guard let string = NSPasteboard.general.string(forType: .string) else { return }
        text = string.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    #endif
}
