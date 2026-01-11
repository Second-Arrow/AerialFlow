import Foundation
import Testing
@testable import AerialFlow

struct SystemAccessProbeTests {
    @Test func testProbe_reportsErrors_whenCatalogMissing_andIndexPlistMissing() throws {
        let fs = InMemoryFileSystem()
        let runner = FakeCommandRunner()
        let detector = ActiveVideoDirectoryDetector(runner: runner, homeDirectoryURL: URL(fileURLWithPath: "/home"))
        let editor = WallpaperStoreEditor(fileSystem: fs)
        let features = AerialFlowFeatures(movDownloadMode: .directToVideoDirectory)

        let probe = SystemAccessProbe(
            fileSystem: fs,
            directoryDetector: detector,
            storeEditor: editor,
            features: features,
            catalogURL: URL(fileURLWithPath: "/missing/entries.json")
        )

        let settings = AppSettings(indexPlistURL: URL(fileURLWithPath: "/missing/Index.plist"))
        let report = probe.probe(settings: settings)

        #expect(report.items.contains(where: { $0.id == "catalog" && $0.state == .error }))
        #expect(report.items.contains(where: { $0.id == "indexPlist" && $0.state != .ok }))
        #expect(report.items.contains(where: { $0.id == "aerialConfiguration" && $0.state != .ok }))
    }

    @Test func testProbe_reportsOk_whenCatalogReadable_andIndexPlistWritable() throws {
        let fs = InMemoryFileSystem()
        let runner = FakeCommandRunner()
        let detector = ActiveVideoDirectoryDetector(runner: runner, homeDirectoryURL: URL(fileURLWithPath: "/home"))
        let editor = WallpaperStoreEditor(fileSystem: fs)
        let features = AerialFlowFeatures(movDownloadMode: .directToVideoDirectory)

        let catalogURL = URL(fileURLWithPath: "/catalog/entries.json")
        let indexURL = URL(fileURLWithPath: "/wallpaper/Index.plist")
        try fs.createDirectory(at: catalogURL.deletingLastPathComponent())
        try fs.createDirectory(at: indexURL.deletingLastPathComponent())
        try fs.writeData(Data("{}".utf8), to: catalogURL, options: [.atomic])
        let configData = try PropertyListSerialization.data(
            fromPropertyList: ["assetID": "A"],
            format: .binary,
            options: 0
        )
        let root: [String: Any] = [
            "SystemDefault": [
                "Linked": [
                    "Content": [
                        "Choices": [
                            [
                                "Provider": "com.apple.wallpaper.choice.aerials",
                                "Configuration": configData,
                            ],
                        ],
                    ],
                ],
            ],
        ]
        let indexData = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        try fs.writeData(indexData, to: indexURL, options: [.atomic])

        let probe = SystemAccessProbe(
            fileSystem: fs,
            directoryDetector: detector,
            storeEditor: editor,
            features: features,
            catalogURL: catalogURL
        )

        let settings = AppSettings(indexPlistURL: indexURL)
        let report = probe.probe(settings: settings)

        #expect(report.items.contains(where: { $0.id == "catalog" && $0.state == .ok }))
        #expect(report.items.contains(where: { $0.id == "indexPlist" && $0.state == .ok }))
        #expect(report.items.contains(where: { $0.id == "aerialConfiguration" }))
    }

    @Test func testProbe_macos15Mode_reportsOk_forIdleassetsdDirectory_evenIfNotWritable() throws {
        let fs = InMemoryFileSystem()
        let runner = FakeCommandRunner()
        runner.stub(
            Command("/usr/bin/pgrep", ["-x", "-n", "WallpaperVideoExtension"]),
            result: CommandResult(exitCode: 0, stdout: "567\n", stderr: "")
        )
        runner.stub(
            Command("/usr/sbin/lsof", ["-nP", "-Fn", "-p", "567"]),
            result: CommandResult(
                exitCode: 0,
                stdout: "p567\nn/Library/Application Support/com.apple.idleassetsd/Customer/4KSDR240FPS/ASSET.mov\n",
                stderr: ""
            )
        )
        let detector = ActiveVideoDirectoryDetector(runner: runner, homeDirectoryURL: URL(fileURLWithPath: "/home"))
        let editor = WallpaperStoreEditor(fileSystem: fs)
        let features = AerialFlowFeatures(movDownloadMode: .relyOnSystemCache_macos15)

        let probe = SystemAccessProbe(
            fileSystem: fs,
            directoryDetector: detector,
            storeEditor: editor,
            features: features,
            catalogURL: URL(fileURLWithPath: "/missing/entries.json")
        )

        let report = probe.probe(settings: AppSettings(indexPlistURL: URL(fileURLWithPath: "/missing/Index.plist")))
        let videos = report.items.first(where: { $0.id == "videos" })

        #expect(videos?.state == .ok)
        #expect(videos?.detail.contains("idleassetsd") == true)
    }
}


