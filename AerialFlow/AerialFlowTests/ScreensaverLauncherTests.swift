import Foundation
import Testing
@testable import AerialFlow

struct ScreensaverLauncherTests {
    @Test func testStart_runsOpenScreenSaverEngine() async throws {
        let runner = FakeCommandRunner()
        runner.stub(
            Command("/usr/bin/open", ["-b", "com.apple.ScreenSaver.Engine"]),
            result: CommandResult(exitCode: 0, stdout: "", stderr: "")
        )

        let launcher = ScreensaverLauncher(runner: runner)
        try launcher.start()

        #expect(runner.invocations == [.init(command: Command("/usr/bin/open", ["-b", "com.apple.ScreenSaver.Engine"]))])
    }

    @Test func testStart_throwsOnNonZeroExit() async {
        let runner = FakeCommandRunner()
        runner.stub(
            Command("/usr/bin/open", ["-b", "com.apple.ScreenSaver.Engine"]),
            result: CommandResult(exitCode: 1, stdout: "", stderr: "nope")
        )

        let launcher = ScreensaverLauncher(runner: runner)

        do {
            try launcher.start()
            #expect(Bool(false), "Expected non-zero exit to throw")
        } catch let error as ScreensaverLauncher.ScreensaverError {
            switch error {
            case .failed(let exitCode, let stderr):
                #expect(exitCode == 1)
                #expect(stderr == "nope")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type")
        }
    }
}


