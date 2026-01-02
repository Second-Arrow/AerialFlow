import Foundation
import Testing

@testable import AerialFlow

struct CatalogTests {
    @Test func testParsesFixtureEntriesJson_tolerant() throws {
        let json = """
        {
          "assets": [
            {
              "id": "ASSET-1",
              "categories": ["cat-1", "cat-2"],
              "url-4K-SDR-240FPS": "https://example.com/a.mov",
              "url-4K": "https://example.com/b.mov",
              "someOtherKey": 123
            },
            {
              "id": "ASSET-2"
            }
          ],
          "categories": [
            { "id": "cat-1", "localizedNameKey": "Earth" },
            { "id": "cat-2", "localizedNameKey": "Underwater" }
          ]
        }
        """

        let decoded = try JSONDecoder().decode(AerialEntries.self, from: Data(json.utf8))
        #expect(decoded.assets.count == 2)
        #expect(decoded.categories.count == 2)

        let first = decoded.assets[0]
        #expect(first.id == "ASSET-1")
        #expect(first.categories == ["cat-1", "cat-2"])
        #expect(first.urlVariants["url-4K-SDR-240FPS"]?.absoluteString == "https://example.com/a.mov")
        #expect(first.urlVariants["url-4K"]?.absoluteString == "https://example.com/b.mov")

        let second = decoded.assets[1]
        #expect(second.id == "ASSET-2")
        #expect(second.categories.isEmpty)
        #expect(second.urlVariants.isEmpty)
    }

    @Test func testAerialCatalog_loadsSnapshotFromFileSystem() async throws {
        let fs = InMemoryFileSystem()
        let catalogURL = URL(fileURLWithPath: "/test/entries.json")
        try fs.createDirectory(at: catalogURL.deletingLastPathComponent())

        let json = """
        {
          "assets": [
            { "id": "A", "categories": ["c1"], "url-4K": "https://example.com/a.mov" }
          ],
          "categories": [
            { "id": "c1", "localizedNameKey": "City" }
          ]
        }
        """
        try fs.writeData(Data(json.utf8), to: catalogURL, options: [])

        let catalog = AerialCatalog(fileURL: catalogURL, fileSystem: fs)
        let snapshot = try await catalog.loadSnapshot()

        #expect(snapshot.assets.count == 1)
        #expect(snapshot.assets[0].id == "A")
        #expect(snapshot.categories.count == 1)
        #expect(snapshot.categories[0].id == "c1")
    }

    @Test func testAerialCatalog_throwsWhenFileNotFound() async {
        let fs = InMemoryFileSystem()
        let catalogURL = URL(fileURLWithPath: "/nonexistent/entries.json")
        let catalog = AerialCatalog(fileURL: catalogURL, fileSystem: fs)

        do {
            _ = try await catalog.loadSnapshot()
            #expect(Bool(false), "Expected error to be thrown")
        } catch let error as AerialCatalog.CatalogError {
            switch error {
            case .fileNotFound:
                #expect(Bool(true))
            default:
                #expect(Bool(false), "Expected fileNotFound error")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type")
        }
    }
}


