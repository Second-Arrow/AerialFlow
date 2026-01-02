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
}


