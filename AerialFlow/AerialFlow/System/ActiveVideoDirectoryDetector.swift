import Foundation

/// Detects the active Aerial videos directory by inspecting the `.mov` currently opened by `WallpaperVideoExtension`.
struct ActiveVideoDirectoryDetector: Sendable {
    struct Detection: Sendable, Equatable {
        let videoDirectory: URL
        let currentMovPath: URL?
    }

    enum DetectorError: LocalizedError {
        case couldNotDetermineHomeDirectory

        var errorDescription: String? {
            switch self {
            case .couldNotDetermineHomeDirectory:
                return "Could not determine the current user's home directory."
            }
        }
    }

    private let runner: CommandRunner
    private let homeDirectoryURL: URL

    init(runner: CommandRunner, homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.runner = runner
        self.homeDirectoryURL = homeDirectoryURL
    }

    func detect() throws -> Detection {
        let defaultDir = try defaultVideosDirectory()
        guard let pid = newestPID(processName: "WallpaperVideoExtension") else {
            return Detection(videoDirectory: defaultDir, currentMovPath: nil)
        }

        guard let movPath = currentMovPath(pid: pid) else {
            return Detection(videoDirectory: defaultDir, currentMovPath: nil)
        }

        return Detection(videoDirectory: movPath.deletingLastPathComponent(), currentMovPath: movPath)
    }

    private func newestPID(processName: String) -> Int? {
        // pgrep -x -n WallpaperVideoExtension
        let cmd = Command("/usr/bin/pgrep", ["-x", "-n", processName])
        let result = try? runner.run(cmd)
        guard let result, result.exitCode == 0 else { return nil }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(trimmed)
    }

    private func currentMovPath(pid: Int) -> URL? {
        // lsof -nP -Fn -p <pid>
        let cmd = Command("/usr/sbin/lsof", ["-nP", "-Fn", "-p", "\(pid)"])
        let result = try? runner.run(cmd)
        guard let result, result.exitCode == 0 else { return nil }

        // lsof -Fn emits lines like: "n/Path/To/File"
        // Lines starting with "n" contain file paths
        for line in result.stdout.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.first == "n", trimmed.count > 1 else { continue }
            let path = String(trimmed.dropFirst())
            guard !path.isEmpty, path.hasSuffix(".mov") else { continue }
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    private func defaultVideosDirectory() throws -> URL {
        let home = homeDirectoryURL
        if home.path.isEmpty {
            throw DetectorError.couldNotDetermineHomeDirectory
        }
        return home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("com.apple.wallpaper", isDirectory: true)
            .appendingPathComponent("aerials", isDirectory: true)
            .appendingPathComponent("videos", isDirectory: true)
    }
}


