import Foundation
import UniformTypeIdentifiers

/// The file a shared animation travels in.
///
/// It's JSON underneath — the same shape the app stores in Application
/// Support — but that's storage, not something to put in a menu. A person
/// exporting an animation to send to a teammate has no use for the format,
/// and "Export All as JSON…" next to "Add from a JSON File…" made the two
/// halves of one errand read as a developer tool.
///
/// So exports get this app's own extension, and imports accept both it and
/// plain `.json` — every file anyone has already exported ends in `.json`,
/// and a rename shouldn't strand them.
enum AnimationDocument {
    /// Not registered as an exported UTType in `Info.plist`. Doing that
    /// properly means Finder icons and a "kind" string, which is a real
    /// piece of work and unverifiable from here — this gets the format out
    /// of the interface without pretending to more than it does.
    static let fileExtension = "nexusanim"

    static var contentType: UTType {
        UTType(filenameExtension: fileExtension) ?? .json
    }

    /// What a save panel should offer. `.json` stays in the list so the
    /// panel doesn't refuse a name someone types with the old extension.
    static var writableTypes: [UTType] { [contentType, .json] }

    /// What an open panel should accept.
    static var readableTypes: [UTType] { [contentType, .json] }

    static func fileName(_ base: String) -> String {
        "\(base).\(fileExtension)"
    }
}
