import Testing
@testable import AerialFlow

struct AboutInfoTests {
    @Test func testVersionLine_whenHasVersionAndBuild() {
        #expect(AboutInfo.versionLine(shortVersion: "1.0", build: "42") == "Version 1.0 (Build 42)")
    }

    @Test func testVersionLine_whenMissingBuildOrVersion() {
        #expect(AboutInfo.versionLine(shortVersion: "1.0", build: nil) == "Version 1.0")
        #expect(AboutInfo.versionLine(shortVersion: nil, build: "42") == "Build 42")
        #expect(AboutInfo.versionLine(shortVersion: nil, build: nil) == "Version —")
    }
}


