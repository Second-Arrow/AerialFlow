import Foundation
import Testing
@testable import AerialFlow

struct ExcludedAerialsCleanerTests {
    @Test func testCleanExcludedMovFiles_removesOnlyExcludedAssets_allExclusions() async throws {
        let fs = InMemoryFileSystem()

        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
        let runner = FakeCommandRunner()
        // No WallpaperVideoExtension process → fall back to default directory under home.
        runner.stub(
            Command("/usr/bin/pgrep", ["-x", "-n", "WallpaperVideoExtension"]),
            result: CommandResult(exitCode: 1, stdout: "", stderr: "")
        )
        let detector = ActiveVideoDirectoryDetector(runner: runner, homeDirectoryURL: home)

        let detection = try detector.detect()
        let videoDir = detection.videoDirectory
        try fs.createDirectory(at: videoDir)

        // Create .mov files for three assets; plus one unrelated file that must remain.
        let a1 = videoDir.appendingPathComponent("A1.mov")
        let a2 = videoDir.appendingPathComponent("A2.mov")
        let a3 = videoDir.appendingPathComponent("A3.mov")
        let keep = videoDir.appendingPathComponent("KEEP.mov")
        try fs.writeData(Data("x".utf8), to: a1, options: [])
        try fs.writeData(Data("x".utf8), to: a2, options: [])
        try fs.writeData(Data("x".utf8), to: a3, options: [])
        try fs.writeData(Data("x".utf8), to: keep, options: [])

        // Catalog fixture.
        let catalogURL = URL(fileURLWithPath: "/test/entries.json")
        try fs.createDirectory(at: catalogURL.deletingLastPathComponent())
        let json = """
        {
          "assets": [
            { "id": "A1", "categories": ["cat-1"], "subcategories": ["sub-1"], "url-4K": "https://example.com/a1.mov" },
            { "id": "A2", "categories": ["cat-2"], "subcategories": [], "url-4K": "https://example.com/a2.mov" },
            { "id": "A3", "categories": [], "subcategories": ["sub-x"], "url-4K": "https://example.com/a3.mov" }
          ],
          "categories": [
            { "id": "cat-1", "localizedNameKey": "Earth" },
            { "id": "cat-2", "localizedNameKey": "City" }
          ]
        }
        """
        try fs.writeData(Data(json.utf8), to: catalogURL, options: [])
        let catalog = AerialCatalog(fileURL: catalogURL, fileSystem: fs)

        let cleaner = ExcludedAerialsCleaner(fileSystem: fs, directoryDetector: detector, catalog: catalog)

        let settings = AppSettings(
            excludedCategoryIDs: ["cat-2"],      // Exclude A2 by main category
            excludedSubcategoryIDs: ["sub-1"],   // Exclude A1 by subcategory
            excludedAssetIDs: ["A3"]             // Exclude A3 explicitly
        )

        let report = try await cleaner.cleanExcludedMovFiles(settings: settings)
        #expect(report.failures.isEmpty)
        #expect(Set(report.removedFiles.map(\.lastPathComponent)) == ["A1.mov", "A2.mov", "A3.mov"])

        #expect(fs.fileExists(at: a1) == false)
        #expect(fs.fileExists(at: a2) == false)
        #expect(fs.fileExists(at: a3) == false)
        #expect(fs.fileExists(at: keep) == true)
    }

    @Test func testCleanExcludedMovFiles_noFilesToRemove_doesNothing() async throws {
        let fs = InMemoryFileSystem()
        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
        let runner = FakeCommandRunner()
        runner.stub(
            Command("/usr/bin/pgrep", ["-x", "-n", "WallpaperVideoExtension"]),
            result: CommandResult(exitCode: 1, stdout: "", stderr: "")
        )
        let detector = ActiveVideoDirectoryDetector(runner: runner, homeDirectoryURL: home)

        let catalogURL = URL(fileURLWithPath: "/test/entries.json")
        try fs.createDirectory(at: catalogURL.deletingLastPathComponent())
        let json = """
        {
          "assets": [
            { "id": "A1", "categories": ["cat-1"], "subcategories": [], "url-4K": "https://example.com/a1.mov" }
          ],
          "categories": [
            { "id": "cat-1", "localizedNameKey": "Earth" }
          ]
        }
        """
        try fs.writeData(Data(json.utf8), to: catalogURL, options: [])
        let catalog = AerialCatalog(fileURL: catalogURL, fileSystem: fs)

        let cleaner = ExcludedAerialsCleaner(fileSystem: fs, directoryDetector: detector, catalog: catalog)
        let settings = AppSettings(excludedCategoryIDs: [], excludedSubcategoryIDs: [], excludedAssetIDs: [])

        let report = try await cleaner.cleanExcludedMovFiles(settings: settings)
        #expect(report.removedCount == 0)
        #expect(report.failures.isEmpty)
    }
}


