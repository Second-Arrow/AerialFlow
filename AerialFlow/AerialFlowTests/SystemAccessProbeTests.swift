import Foundation
import Testing
@testable import AerialFlow

struct SystemAccessProbeTests {
    @Test func testProbe_reportsErrors_whenCatalogMissing_andIndexPlistMissing() throws {
        let fs = InMemoryFileSystem()
        let runner = FakeCommandRunner()
        let detector = ActiveVideoDirectoryDetector(runner: runner, homeDirectoryURL: URL(fileURLWithPath: "/home"))
        let editor = WallpaperStoreEditor(fileSystem: fs)

        let probe = SystemAccessProbe(
            fileSystem: fs,
            directoryDetector: detector,
            storeEditor: editor,
            catalogURL: URL(fileURLWithPath: "/missing/entries.json")
        )

        let settings = AppSettings(indexPlistURL: URL(fileURLWithPath: "/missing/Index.plist"))
        let report = probe.probe(settings: settings)

        #expect(report.items.contains(where: { $0.id == "catalog" && $0.state == .error }))
        #expect(report.items.contains(where: { $0.id == "indexPlist" && $0.state != .ok }))
    }

    @Test func testProbe_reportsOk_whenCatalogReadable_andIndexPlistWritable() throws {
        let fs = InMemoryFileSystem()
        let runner = FakeCommandRunner()
        let detector = ActiveVideoDirectoryDetector(runner: runner, homeDirectoryURL: URL(fileURLWithPath: "/home"))
        let editor = WallpaperStoreEditor(fileSystem: fs)

        let catalogURL = URL(fileURLWithPath: "/catalog/entries.json")
        let indexURL = URL(fileURLWithPath: "/wallpaper/Index.plist")
        try fs.createDirectory(at: catalogURL.deletingLastPathComponent())
        try fs.createDirectory(at: indexURL.deletingLastPathComponent())
        try fs.writeData(Data("{}".utf8), to: catalogURL, options: [.atomic])
        try fs.writeData(Data(), to: indexURL, options: [.atomic])

        let probe = SystemAccessProbe(
            fileSystem: fs,
            directoryDetector: detector,
            storeEditor: editor,
            catalogURL: catalogURL
        )

        let settings = AppSettings(indexPlistURL: indexURL)
        let report = probe.probe(settings: settings)

        #expect(report.items.contains(where: { $0.id == "catalog" && $0.state == .ok }))
        #expect(report.items.contains(where: { $0.id == "indexPlist" && $0.state == .ok }))
    }
}


