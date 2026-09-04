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
    /// Omit for a column with nothing to search.
    var search: Binding<String>?
    var searchPrompt: String = "Search"
    /// The one labelled action a column may have, shown at the leading
    /// edge of the action bar. Everything in `actions` is icon-only.
    var header: AnyView?
    @ViewBuilder var content: () -> Content
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 0) {
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

    private var actionBar: some View {
        HStack(spacing: 6) {
            // The labelled action first, then the icons, so the row reads
            // left to right from "the thing you'd look for" to "the things
            // you already know".
            if let header {
                header
                Spacer(minLength: 6)
            } else {
                Spacer(minLength: 0)
            }
            actions()
                .labelStyle(.iconOnly)
                .menuIndicator(.hidden)
                .fixedSize(horizontal: false, vertical: true)
        }
        // Real Liquid Glass, not `.plain`. These sat in the window toolbar
        // originally, where the system applies it for free; moving them
        // into the column is what lost it — the same trade-off
        // `ControlsView` notes about moving its cards off `Form`.
        .ringGlassButtonStyle()
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.top, 10)
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
        search: Binding<String>? = nil,
        searchPrompt: String = "Search",
        header: AnyView? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.search = search
        self.searchPrompt = searchPrompt
        self.header = header
        self.content = content
        self.actions = { EmptyView() }
    }
}
