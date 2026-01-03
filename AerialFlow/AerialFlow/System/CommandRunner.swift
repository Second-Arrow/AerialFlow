import Foundation

/// A small seam around running system commands, to keep `Core/` testable.
protocol CommandRunner: Sendable {
    @discardableResult
    func run(_ command: Command) throws -> CommandResult
}

struct Command: Sendable, Equatable, Hashable {
    let launchPath: String
    let arguments: [String]

    init(_ launchPath: String, _ arguments: [String] = []) {
        self.launchPath = launchPath
        self.arguments = arguments
    }
}

struct CommandResult: Sendable, Equatable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

final class ProcessCommandRunner: CommandRunner {
    init() {}

    func run(_ command: Command) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.launchPath)
        process.arguments = command.arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        let result = CommandResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
        return result
    }
}

