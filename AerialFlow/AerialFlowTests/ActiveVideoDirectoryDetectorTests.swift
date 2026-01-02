import Foundation
import Testing

@testable import AerialFlow

struct ActiveVideoDirectoryDetectorTests {
    @Test func testDetect_usesMovFromLsof() throws {
        let runner = FakeCommandRunner()
        runner.stub(
            Command("/usr/bin/pgrep", ["-x", "-n", "WallpaperVideoExtension"]),
            result: CommandResult(exitCode: 0, stdout: "123\n", stderr: "")
        )
        runner.stub(
            Command("/usr/sbin/lsof", ["-nP", "-Fn", "-p", "123"]),
            result: CommandResult(exitCode: 0, stdout: "p123\nn/Users/me/Library/Application Support/com.apple.wallpaper/aerials/videos/ASSET.mov\n", stderr: "")
        )

        let detector = ActiveVideoDirectoryDetector(runner: runner)
        let detection = try detector.detect()
        #expect(detection.currentMovPath?.path.hasSuffix("/ASSET.mov") == true)
        #expect(detection.videoDirectory.path.hasSuffix("/videos") == true)
    }
}


