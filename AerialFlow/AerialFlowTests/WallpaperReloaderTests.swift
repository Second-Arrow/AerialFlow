import Foundation
import Testing

@testable import AerialFlow

struct WallpaperReloaderTests {
    @Test func testReload_invokesExpectedCommands() {
        let runner = FakeCommandRunner()
        runner.stub(Command("/usr/bin/pkill", ["-x", "WallpaperVideoExtension"]), result: .init(exitCode: 1, stdout: "", stderr: ""))
        runner.stub(Command("/usr/bin/killall", ["WallpaperAgent"]), result: .init(exitCode: 0, stdout: "", stderr: ""))

        let reloader = WallpaperReloader(runner: runner)
        reloader.reloadWallpaperPipelines()

        let commands = runner.invocations.map(\.command)
        #expect(commands == [
            Command("/usr/bin/pkill", ["-x", "WallpaperVideoExtension"]),
            Command("/usr/bin/killall", ["WallpaperAgent"]),
        ])
    }

    @Test func testIsExpectedProcessNotFoundError_pkillWithTaskPortRightError() {
        let reloader = WallpaperReloader(runner: FakeCommandRunner())
        let stderr = "Unable to obtain a task name port right for pid 400: (os/kern) failure (0x5)"
        #expect(reloader.isExpectedProcessNotFoundError(exitCode: 1, stderr: stderr) == true)
    }

    @Test func testIsExpectedProcessNotFoundError_pkillWithNoMatchingProcesses() {
        let reloader = WallpaperReloader(runner: FakeCommandRunner())
        let stderr = "No matching processes were found"
        #expect(reloader.isExpectedProcessNotFoundError(exitCode: 1, stderr: stderr) == true)
    }

    @Test func testIsExpectedProcessNotFoundError_pkillWithEmptyStderr() {
        let reloader = WallpaperReloader(runner: FakeCommandRunner())
        #expect(reloader.isExpectedProcessNotFoundError(exitCode: 1, stderr: "") == true)
    }

    @Test func testIsExpectedProcessNotFoundError_killallWithNoMatchingProcesses() {
        let reloader = WallpaperReloader(runner: FakeCommandRunner())
        let stderr = "No matching processes were found"
        #expect(reloader.isExpectedProcessNotFoundError(exitCode: 1, stderr: stderr) == true)
    }

    @Test func testIsExpectedProcessNotFoundError_unexpectedError() {
        let reloader = WallpaperReloader(runner: FakeCommandRunner())
        let stderr = "Permission denied"
        #expect(reloader.isExpectedProcessNotFoundError(exitCode: 1, stderr: stderr) == false)
    }

    @Test func testIsExpectedProcessNotFoundError_exitCodeNotOne() {
        let reloader = WallpaperReloader(runner: FakeCommandRunner())
        #expect(reloader.isExpectedProcessNotFoundError(exitCode: 2, stderr: "") == false)
    }
}


