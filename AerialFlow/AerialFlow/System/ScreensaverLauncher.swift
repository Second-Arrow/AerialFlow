import Foundation

protocol ScreensaverLaunching: Sendable {
    func start() throws
}

struct ScreensaverLauncher: ScreensaverLaunching {
    enum ScreensaverError: LocalizedError, Sendable {
        case failed(exitCode: Int32, stderr: String)

        var errorDescription: String? {
            switch self {
            case .failed(let exitCode, let stderr):
                let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    return "Failed to start the screensaver (exit code \(exitCode))."
                }
                return "Failed to start the screensaver (exit code \(exitCode)): \(trimmed)"
            }
        }
    }

    private let runner: CommandRunner

    init(runner: CommandRunner) {
        self.runner = runner
    }

    func start() throws {
        let result = try runner.run(Command("/usr/bin/open", ["-b", "com.apple.ScreenSaver.Engine"]))
        guard result.exitCode == 0 else {
            throw ScreensaverError.failed(exitCode: result.exitCode, stderr: result.stderr)
        }
    }
}


