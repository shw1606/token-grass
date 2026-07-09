import Foundation

/// A safe, best-effort nudge for Claude Code to refresh its own OAuth credentials.
///
/// If the Mac was asleep/off for a while, nothing ever ran `claude` to trigger
/// its normal refresh-on-use logic, so the access token in the Keychain can sit
/// expired until the user manually opens a terminal and runs `claude` again —
/// which is the only thing that was fixing our 401s.
///
/// We deliberately do NOT refresh the OAuth token ourselves: Anthropic's refresh
/// tokens may rotate on use, and if we exchanged it directly (bypassing Claude
/// Code), we could invalidate the very credential Claude Code itself relies on —
/// trading a cosmetic "please run claude" message for an actual forced logout.
/// Instead, we just invoke Claude Code's own `claude auth status` — a fast,
/// non-interactive, read-only command that makes an authenticated check and,
/// like any well-behaved OAuth client, refreshes and persists its own token
/// (correctly, in its own format) if that's what it decides is needed. We then
/// simply re-read the Keychain to see whatever it left there.
enum ClaudeAuthNudge {
    /// Best-effort; never throws. Times out quickly so a hung subprocess can't
    /// stall a sync() call.
    static func refresh() async {
        guard let claudePath = findClaude() else {
            SyncLog.log("auth nudge: claude binary not found")
            return
        }
        await Task.detached(priority: .utility) {
            run(claudePath)
        }.value
    }

    private static func run(_ claudePath: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["auth", "status"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            SyncLog.log("auth nudge: failed to launch (\(error.localizedDescription))")
            return
        }

        // No built-in timeout on Process — bound it ourselves so a hang here
        // can't wedge the caller beyond a few seconds.
        let deadline = Date().addingTimeInterval(8)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            process.terminate()
            SyncLog.log("auth nudge: timed out, terminated")
        } else {
            SyncLog.log("auth nudge: claude auth status exited \(process.terminationStatus)")
        }
    }

    private static func findClaude() -> String? {
        let fm = FileManager.default
        let candidates = [
            "\(NSHomeDirectory())/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "/usr/bin/claude",
        ]
        for path in candidates where fm.isExecutableFile(atPath: path) { return path }

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lc", "command -v claude"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        let resolved = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let resolved, !resolved.isEmpty, fm.isExecutableFile(atPath: resolved) { return resolved }
        return nil
    }
}
