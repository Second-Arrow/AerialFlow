import Testing
@testable import AerialFlow

struct RunGuardTests {
    @Test func testShouldRunNow_falseWhenConsoleOwnerIsRoot() async throws {
        let runner = FakeCommandRunner()
        runner.stub(
            Command("/usr/bin/stat", ["-f", "%Su", "/dev/console"]),
            result: CommandResult(exitCode: 0, stdout: "root\n", stderr: "")
        )

        let guarder = RunGuard(runner: runner)
        #expect(guarder.shouldRunNow(settings: AppSettings()) == false)
    }

    @Test func testShouldRunNow_falseWhenScreenSaverEngineIsRunning() async throws {
        let runner = FakeCommandRunner()
        runner.stub(
            Command("/usr/bin/stat", ["-f", "%Su", "/dev/console"]),
            result: CommandResult(exitCode: 0, stdout: "floris\n", stderr: "")
        )
        runner.stub(
            Command("/usr/bin/pgrep", ["-x", "ScreenSaverEngine"]),
            result: CommandResult(exitCode: 0, stdout: "123\n", stderr: "")
        )

        let guarder = RunGuard(runner: runner)
        #expect(guarder.shouldRunNow(settings: AppSettings()) == false)
    }

    @Test func testShouldRunNow_falseWhenDisplayPowerStateIsOff() async throws {
        let runner = FakeCommandRunner()
        runner.stub(
            Command("/usr/bin/stat", ["-f", "%Su", "/dev/console"]),
            result: CommandResult(exitCode: 0, stdout: "floris\n", stderr: "")
        )
        runner.stub(
            Command("/usr/bin/pgrep", ["-x", "ScreenSaverEngine"]),
            result: CommandResult(exitCode: 1, stdout: "", stderr: "")
        )
        runner.stub(
            Command("/usr/sbin/ioreg", ["-n", "IODisplayWrangler", "-r", "-d", "1"]),
            result: CommandResult(exitCode: 0, stdout: "\"CurrentPowerState\"=1\n", stderr: "")
        )

        let guarder = RunGuard(runner: runner)
        #expect(guarder.shouldRunNow(settings: AppSettings()) == false)
    }

    @Test func testShouldRunNow_trueWhenAllChecksPass() async throws {
        let runner = FakeCommandRunner()
        runner.stub(
            Command("/usr/bin/stat", ["-f", "%Su", "/dev/console"]),
            result: CommandResult(exitCode: 0, stdout: "floris\n", stderr: "")
        )
        runner.stub(
            Command("/usr/bin/pgrep", ["-x", "ScreenSaverEngine"]),
            result: CommandResult(exitCode: 1, stdout: "", stderr: "")
        )
        runner.stub(
            Command("/usr/sbin/ioreg", ["-n", "IODisplayWrangler", "-r", "-d", "1"]),
            result: CommandResult(exitCode: 0, stdout: "\"CurrentPowerState\"=4\n", stderr: "")
        )

        let guarder = RunGuard(runner: runner)
        #expect(guarder.shouldRunNow(settings: AppSettings()) == true)
    }
}


