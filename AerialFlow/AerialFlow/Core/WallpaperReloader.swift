import Foundation
import os

/// Best-effort restart of wallpaper processes to force the new video to load.
struct WallpaperReloader: Sendable {
    private let logger = Logger(subsystem: "com.secondarrow.AerialFlow", category: "WallpaperReloader")
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
                logger.debug("Command exited non-zero (\(result.exitCode)): \(command.launchPath, privacy: .public)")
            }
        } catch {
            logger.debug("Command failed: \(command.launchPath, privacy: .public) \(String(describing: error), privacy: .public)")
        }
    }
}

// MARK: - Protocol Conformance

extension WallpaperReloader: WallpaperReloading {}


