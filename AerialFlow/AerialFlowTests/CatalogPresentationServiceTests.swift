import Foundation
import Testing
@testable import AerialFlow

private struct FakeCatalog: AerialCataloging {
    let snapshot: AerialCatalog.Snapshot
    func loadSnapshot() async throws -> AerialCatalog.Snapshot { snapshot }
}

private struct FailingCatalog: AerialCataloging {
    struct TestError: Error {}
    func loadSnapshot() async throws -> AerialCatalog.Snapshot { throw TestError() }
}

struct CatalogPresentationServiceTests {
    @Test func testResolvesCategoryAndAssetNamesFromStringsBundle() async throws {
        let fs = InMemoryFileSystem()
        let bundleRoot = URL(fileURLWithPath: "/TVIdleScreenStrings.bundle", isDirectory: true)
        let enLproj = bundleRoot.appendingPathComponent("en.lproj", isDirectory: true)
        try fs.createDirectory(at: bundleRoot)
        try fs.createDirectory(at: enLproj)

        let stringsURL = enLproj.appendingPathComponent("Localizable.strings")
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Earth</key>
          <string>Earth Display</string>
          <key>AssetKey</key>
          <string>Pretty A</string>
        </dict>
        </plist>
        """
        try fs.writeData(Data(plist.utf8), to: stringsURL, options: [])

        let resolver = CategoryResolver(fileSystem: fs, bundleRootURL: bundleRoot)

        let asset = AerialAsset(
            id: "a",
            categories: ["cat1"],
            subcategories: ["sub1"],
            localizedNameKey: "AssetKey",
            urlVariants: ["url-4K": URL(string: "https://example.com/a.mov")!]
        )
        let category = AerialCategory(id: "cat1", localizedNameKey: "Earth")
        let snapshot = AerialCatalog.Snapshot(
            assets: [asset],
            categories: [category],
            fileURL: URL(fileURLWithPath: "/dev/null"),
            fileModificationDate: nil
        )

        let service = CatalogPresentationService(catalog: FakeCatalog(snapshot: snapshot), resolver: resolver)

        let categoryNames = await service.categoryDisplayNamesByID(categories: [category])
        #expect(categoryNames["cat1"] == "Earth Display")

        let assetNames = await service.assetDisplayNamesByID(assets: [asset])
        #expect(assetNames["a"] == "Pretty A")

        let single = await service.assetDisplayName(for: "a")
        #expect(single == "Pretty A")

        let subs = await service.subcategoryIDs(for: "a")
        #expect(subs == Set(["sub1"]))
    }

    @Test func testAssetDisplayNamesByID_usesFullFallbackChain() async throws {
        let fs = InMemoryFileSystem()
        let bundleRoot = URL(fileURLWithPath: "/TVIdleScreenStrings.bundle", isDirectory: true)
        try fs.createDirectory(at: bundleRoot) // empty bundle -> no strings resolve

        let resolver = CategoryResolver(fileSystem: fs, bundleRootURL: bundleRoot)

        // Asset has no resolvable localized name, but does carry an accessibilityLabel.
        let asset = AerialAsset(
            id: "mac-1",
            categories: ["mac-cat"],
            localizedNameKey: "MAC_WP_PPL_NAME",
            accessibilityLabel: "Mac Purple",
            urlVariants: [:]
        )
        let snapshot = AerialCatalog.Snapshot(
            assets: [asset],
            categories: [],
            fileURL: URL(fileURLWithPath: "/dev/null"),
            fileModificationDate: nil
        )
        let service = CatalogPresentationService(catalog: FakeCatalog(snapshot: snapshot), resolver: resolver)

        let names = await service.assetDisplayNamesByID(assets: [asset])
        #expect(names["mac-1"] == "Mac Purple")
    }

    @Test func testFallbacksWhenCatalogLoadFails() async {
        let fs = InMemoryFileSystem()
        let bundleRoot = URL(fileURLWithPath: "/TVIdleScreenStrings.bundle", isDirectory: true)
        let resolver = CategoryResolver(fileSystem: fs, bundleRootURL: bundleRoot)
        let service = CatalogPresentationService(catalog: FailingCatalog(), resolver: resolver)

        let name = await service.assetDisplayName(for: "missing")
        #expect(name == "missing")

        let subs = await service.subcategoryIDs(for: "missing")
        #expect(subs.isEmpty)
    }
}

