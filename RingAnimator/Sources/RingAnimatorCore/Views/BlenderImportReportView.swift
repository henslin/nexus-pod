import SwiftUI

/// What a foreign Blender script import actually did.
///
/// Shown every time rather than only on partial success, because "it
/// worked" is the wrong summary for an interpretation: the ring changing
/// on screen tells you *something* happened, not which knobs moved or
/// which parts of the script had nowhere to go. Reading the dropped list
/// is how you find out the render won't match, before wondering why.
public struct BlenderImportReportView: View {
    let fileName: String
    let outcome: BlenderScriptImporter.Outcome
    let onDismiss: () -> Void

    public init(
        fileName: String,
        outcome: BlenderScriptImporter.Outcome,
        onDismiss: @escaping () -> Void
    ) {
        self.fileName = fileName
        self.outcome = outcome
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(outcome.isEmpty ? "Nothing to import" : "Imported \(fileName)")
                    .font(.headline)
                // On an empty result the caveat is the explanation, so it's
                // promoted here rather than repeated below. There are two
                // readers behind this sheet now, and each one fails for its
                // own reason — a hardcoded line describing only the
                // uppercase-constant scraper told someone importing a
                // firmware pattern module to go looking for a problem that
                // wasn't theirs.
                Text(outcome.isEmpty
                     ? (outcome.caveat ?? "Nothing in this file mapped onto anything this app renders.")
                     : "An interpretation, not a copy. Here's exactly what changed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Scrolls because the report grows with the file: a pattern
            // that states a dozen knobs and drops half of them is a taller
            // sheet than the screen, and the Done button below must stay
            // reachable.
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !outcome.applied.isEmpty {
                        section("Applied", items: outcome.applied, symbol: "checkmark.circle", tint: .green)
                    }

                    if let caveat = outcome.caveat, !outcome.isEmpty {
                        Label(caveat, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !outcome.dropped.isEmpty {
                        section(
                            "Not carried over",
                            items: outcome.dropped,
                            symbol: "minus.circle",
                            tint: .secondary
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 420)

            HStack {
                Spacer()
                Button("Done", action: onDismiss)
                    .keyboardShortcut(.defaultAction)
                    .ringGlassButtonStyle()
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    @ViewBuilder
    private func section(_ title: String, items: [String], symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(items, id: \.self) { item in
                Label {
                    Text(item)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: symbol)
                        .foregroundStyle(tint)
                }
            }
        }
    }
}
