import Foundation
import os

protocol RunGuarding: Sendable {
    nonisolated
    func shouldRunNow(settings: any RunGuardSettings) -> Bool
}

/// Guardrail checks to avoid rotating wallpapers at bad times (login window, screensaver, display off).
///
/// This is intentionally best-effort: if a check cannot be evaluated due to command failures,
/// we fail open rather than permanently disabling rotation.
struct RunGuard: RunGuarding, Sendable {
    private let logger = Logger(subsystem: "com.secondarrow.AerialFlow", category: "RunGuard")

    private let runner: CommandRunner

    init(runner: CommandRunner) {
        self.runner = runner
    }

    func shouldRunNow(settings: any RunGuardSettings) -> Bool {
        if settings.skipAtLoginWindow, isConsoleUserRoot() {
            logger.debug("Blocked: console user is root (login window).")
            return false
        }

        if settings.skipWhenScreensaverActive, isScreenSaverEngineActive() {
            logger.debug("Blocked: ScreenSaverEngine is active.")
            return false
        }

        if settings.skipWhenDisplayOff, isDisplayOffOrSleeping() {
            logger.debug("Blocked: display power state indicates off/sleep.")
            return false
        }

        return true
    }

    private func isConsoleUserRoot() -> Bool {
        // stat -f %Su /dev/console
        let cmd = Command("/usr/bin/stat", ["-f", "%Su", "/dev/console"])
        guard let result = try? runner.run(cmd), result.exitCode == 0 else {
            return false
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "root"
    }

    private func isScreenSaverEngineActive() -> Bool {
        // pgrep -x ScreenSaverEngine
        let cmd = Command("/usr/bin/pgrep", ["-x", "ScreenSaverEngine"])
        guard let result = try? runner.run(cmd) else {
            return false
        }
        // pgrep returns exit 0 if it finds at least one matching PID.
        return result.exitCode == 0
    }

    private func isDisplayOffOrSleeping() -> Bool {
        // ioreg -n IODisplayWrangler -r -d 1
        let cmd = Command("/usr/sbin/ioreg", ["-n", "IODisplayWrangler", "-r", "-d", "1"])
        guard let result = try? runner.run(cmd), result.exitCode == 0 else {
            return false
        }

        guard let powerState = Self.parseCurrentPowerState(from: result.stdout) else {
            return false
        }
        return powerState <= 1
    }

    static func parseCurrentPowerState(from ioregOutput: String) -> Int? {
        // Example fragments seen in the wild:
        // - "\"CurrentPowerState\"=4"
        // - "CurrentPowerState\" = 1"
        //
        // We keep parsing intentionally loose: locate the token, then extract the first integer that follows.
        let token = "CurrentPowerState"
        guard let tokenRange = ioregOutput.range(of: token) else { return nil }
        let tail = ioregOutput[tokenRange.upperBound...]

        var foundDigits = ""
        var started = false
        for scalar in tail.unicodeScalars {
            if CharacterSet.decimalDigits.contains(scalar) {
                started = true
                foundDigits.unicodeScalars.append(scalar)
            } else if started {
                break
            }
        }

        guard !foundDigits.isEmpty else { return nil }
        return Int(foundDigits)
    }
}


