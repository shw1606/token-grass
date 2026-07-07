import Foundation

/// Small on-disk trace of every sync attempt, so a recurring issue can be
/// diagnosed from hard evidence (exact timestamps, HTTP statuses, which guard
/// fired) instead of guesswork. Lives next to accumulator.json; capped so it
/// never grows unbounded.
enum SyncLog {
    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TokenGrass", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("sync.log")
    }

    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func log(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        let url = fileURL
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
        } else {
            try? Data(line.utf8).write(to: url)
        }
        trimIfNeeded(url)
    }

    /// Keep only the most recent ~500 lines so the file can't grow unbounded.
    private static func trimIfNeeded(_ url: URL) {
        guard let data = try? Data(contentsOf: url), data.count > 200_000,
              let text = String(data: data, encoding: .utf8) else { return }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count > 500 else { return }
        let trimmed = lines.suffix(500).joined(separator: "\n") + "\n"
        try? Data(trimmed.utf8).write(to: url)
    }
}
