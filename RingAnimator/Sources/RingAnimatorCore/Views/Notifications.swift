import Foundation

/// Cross-view signals that can't be a binding.
///
/// Both of these cross a boundary SwiftUI state doesn't: a `CommandGroup`
/// in the `App` can't reach into a window's `@State`, and the Use Cases
/// column can't reach the detail view's `@StateObject`. They live in the
/// core rather than the macOS target because the receivers do.
public extension Notification.Name {
    /// Posted by the Help menu item; `ContentView` presents the sheet.
    static let showWhatsNew = Notification.Name("nexus.showWhatsNew")

    /// Posted by the Use Cases column's Import Blender button. The
    /// selected use case's detail view runs it, since it owns the config
    /// being written into — and only that one is mounted, so exactly one
    /// listener answers.
    static let importBlenderIntoUseCase = Notification.Name("nexus.importBlenderIntoUseCase")
}
