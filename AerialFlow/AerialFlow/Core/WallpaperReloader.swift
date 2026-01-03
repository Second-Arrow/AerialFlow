import Foundation
import os

/// Best-effort restart of wallpaper processes to force the new video to load.
struct WallpaperReloader: Sendable {
    private let logger = Logger(subsystem: Constants.loggerSubsystem, category: "WallpaperReloader")
    private let runner: CommandRunner

    init(runner: CommandRunner) {
        self.runner = runner
    }

    func reloadWallpaperPipelines() {
        // Best-effort: ignore failures (process may not be running).
        runBestEffort(Command("/usr/bin/pkill", ["-x", "WallpaperVideoExtension"]))
        runBestEffort(Command("/usr/bin/killall", ["WallpaperAgent"]))
    }

    private func runBestEffort(_ command: Command) {
        do {
            let result = try runner.run(command)
            if result.exitCode != 0 {
                // Only log if it's not an expected "process not found" error
                if !isExpectedProcessNotFoundError(exitCode: result.exitCode, stderr: result.stderr) {
                    logger.debug("Command exited non-zero (\(result.exitCode)): \(command.launchPath, privacy: .public)")
                }
            }
        } catch {
            logger.debug("Command failed: \(command.launchPath, privacy: .public) \(String(describing: error), privacy: .public)")
        }
    }

    /// Returns `true` if the error represents an expected "process not found" scenario.
    ///
    /// For `pkill` and `killall`, exit code 1 with certain stderr messages indicates
    /// the process doesn't exist, which is expected and should be silently ignored.
    func isExpectedProcessNotFoundError(exitCode: Int32, stderr: String) -> Bool {
        guard exitCode == 1 else { return false }
        
        let stderrLower = stderr.lowercased()
        let stderrTrimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Empty stderr with exit code 1 is common when process doesn't exist
        if stderrTrimmed.isEmpty {
            return true
        }
        
        // pkill/killall error messages for "process not found"
        if stderrLower.contains("unable to obtain a task name port right") ||
           stderrLower.contains("no matching processes") {
            return true
        }
        
        return false
    }
}

// MARK: - Protocol Conformance

extension WallpaperReloader: WallpaperReloading {}


