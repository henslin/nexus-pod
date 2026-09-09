import Foundation

/// A plain-text trail of what an export actually did.
///
/// Temporary, and deliberately dumb. "The export doesn't write a file" has
/// survived three rounds of reasoning about code that demonstrably works
/// when driven directly — every combination of transparency, dithering and
/// canvas writes a file in `BlendCheck`. So the question isn't whether the
/// exporter works, it's what the app hands it, and the cheapest way to
/// know is to have the app say so.
///
/// Writes to ~/Library/Logs/NexusPod/export.log, appending. Never throws
/// and never blocks the export: a diagnostic that can fail the thing it is
/// diagnosing is worse than none.
public enum ExportLog {
    public static let url: URL = {
        // `homeDirectoryForCurrentUser` is macOS-only, and this file is in
        // the shared core — the iOS target compiles it too.
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = library.appendingPathComponent("Logs/NexusPod", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("export.log")
    }()

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    public static func note(_ message: String) {
        let line = "\(formatter.string(from: Date()))  \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
