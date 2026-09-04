import SwiftUI

/// The shared anatomy of the three source-list columns: an optional search
/// field at the top, the list, and the column's own actions along the
/// bottom.
///
/// All of it used to live in the *window* toolbar. On macOS a
/// `NavigationSplitView` hoists both `.searchable` and a column's
/// `ToolbarItem`s up there, where they render right-aligned above the
/// detail pane — so the Cue Library's search field sat at the far right of
/// the window, about as far from the list it filters as the geometry
/// allows, and the same went for every Import/Export/Add button. Nothing
/// said which column any of them belonged to.
///
/// Putting them inside the column is the Finder/Xcode/Mail convention for
/// a source list, and it makes the association structural rather than
/// something you have to learn.
struct ListColumn<Content: View, Actions: View>: View {
    /// Names the column, with a line under it saying what's in it — the
    /// arrangement Mail uses for "Inbox — iCloud / All Mail · 628,761
    /// messages". The window title showed the app's name here, which every
    /// section already shares, and before that the selected row's name,
    /// which the highlighted row already said.
    var title: String
    var subtitle: String?
    /// Omit for a column with nothing to search.
    var search: Binding<String>?
    var searchPrompt: String = "Search"
    @ViewBuilder var content: () -> Content
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.title3.weight(.bold))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Actions at the *top*, above the search field. They were along
            // the bottom, which is the Finder/Xcode convention for a source
            // list — but those bars sit at the bottom of a window, and this
            // one sat mid-screen against the timeline strip, reading as
            // part of it rather than as part of the column.
            actionBar
            if let search {
                searchField(search)
            }
            Divider()
            content()
        }
    }

    /// Whatever groups the column hands it, laid out trailing.
    ///
    /// The glass belongs to each `ColumnActionGroup`, not to this bar — one
    /// capsule around everything made four unrelated controls look like one
    /// control with four parts, and adding rules inside it only said where
    /// the seams were. A control that stands alone gets its own circle; a
    /// pair that genuinely belongs together shares a capsule.
    private var actionBar: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            actions()
        }
        .padding(.horizontal, 10)
        .padding(.bottom, search == nil ? 10 : 8)
    }

    private func searchField(_ text: Binding<String>) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.callout)
            // A plain `TextField`, deliberately. See `PasteableTextField`:
            // there is a standing text-input bug on this Xcode beta where
            // typing never reaches a TextField hosted in the app's own view
            // hierarchy, and the toolbar-hosted `.searchable` field this
            // replaces may well have been working *because* the system
            // hosted it. `Package.swift`'s linker-embedded Info.plist was
            // the fix for the underlying cause and has never been confirmed
            // against a text field. If typing here does nothing, that's the
            // bug — not this layout — and the fastest check is whether the
            // Save dialog's field accepts typing either.
            TextField(searchPrompt, text: text)
                .textFieldStyle(.plain)
            if !text.wrappedValue.isEmpty {
                Button {
                    text.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

extension ListColumn where Actions == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        search: Binding<String>? = nil,
        searchPrompt: String = "Search",
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.search = search
        self.searchPrompt = searchPrompt
        self.content = content
        self.actions = { EmptyView() }
    }
}

/// One glass control. A single button comes out a circle; two or three
/// related ones share a capsule, ruled apart by `ColumnActionDivider`.
///
/// Which is the point: grouping should be something you can see rather than
/// infer from the order. Import-from-Blender and import-a-pattern-folder
/// are one control with two buttons; New and Share are not.
struct ColumnActionGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 6) {
            content()
        }
        .labelStyle(.iconOnly)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        // Fixed height and font so a heavier or wider SF Symbol can't make
        // its control taller than the one beside it. With this padding a
        // lone icon comes out square, which a capsule renders as a circle.
        .font(.system(size: 13, weight: .medium))
        .frame(height: 22)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .glassBackground(in: Capsule())
    }
}

/// A hairline inside a `ColumnActionGroup`.
struct ColumnActionDivider: View {
    var body: some View {
        Divider()
            .frame(height: 15)
            .padding(.horizontal, 1)
    }
}
