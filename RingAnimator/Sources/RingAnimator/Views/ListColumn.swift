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
    /// Sits above the search field, where a list's section title would
    /// otherwise be. For actions that belong to the column as a whole
    /// rather than to a row in it.
    var header: AnyView?
    @ViewBuilder var content: () -> Content
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 0) {
            if let header {
                header
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    .padding(.bottom, search == nil ? 8 : 0)
                if search == nil { Divider() }
            }
            if let search {
                searchField(search)
                Divider()
            }
            content()
            Divider()
            HStack(spacing: 4) {
                actions()
                Spacer(minLength: 0)
            }
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
            // A `Menu` in here would otherwise draw its own chevron and
            // stretch to fill the bar, which is not what the other buttons
            // in the row do.
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
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
