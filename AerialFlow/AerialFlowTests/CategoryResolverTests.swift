import Foundation
import Testing

@testable import AerialFlow

struct CategoryResolverTests {
    private func stringsPlistXML(_ dict: [String: String]) -> Data {
        // Minimal XML plist for PropertyListSerialization.
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        """
        for (k, v) in dict.sorted(by: { $0.key < $1.key }) {
            let ek = k.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            let ev = v.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            xml += "<key>\(ek)</key><string>\(ev)</string>"
        }
        xml += """
        </dict>
        </plist>
        """
        return Data(xml.utf8)
    }

    /// Builds a compiled-loctable-shaped plist: `{ locale: { key: value } }`.
    private func loctableXML(_ byLocale: [String: [String: String]]) -> Data {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        }
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        """
        for (locale, table) in byLocale.sorted(by: { $0.key < $1.key }) {
            xml += "<key>\(esc(locale))</key><dict>"
            for (k, v) in table.sorted(by: { $0.key < $1.key }) {
                xml += "<key>\(esc(k))</key><string>\(esc(v))</string>"
            }
            xml += "</dict>"
        }
        xml += "</dict></plist>"
        return Data(xml.utf8)
    }

    @Test func testLoadAllLocalizedStrings_readsLoctableFormat() async throws {
        let fs = InMemoryFileSystem()
        let bundleRoot = URL(fileURLWithPath: "/Bundle", isDirectory: true)
        let resources = bundleRoot
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
        try fs.createDirectory(at: bundleRoot)
        try fs.createDirectory(at: resources)

        try fs.writeData(
            loctableXML(["en": ["MAC_WP_PPL_NAME": "Mac Purple"]]),
            to: resources.appendingPathComponent("Localizable.nocache.loctable"),
            options: [.atomic]
        )

        let resolver = CategoryResolver(fileSystem: fs, bundleRootURL: bundleRoot)
        let name = await resolver.assetName(for: "MAC_WP_PPL")
        #expect(name == "Mac Purple")
    }

    @Test func testAssetName_fallsBackToAccessibilityLabel() async throws {
        let fs = InMemoryFileSystem()
        let bundleRoot = URL(fileURLWithPath: "/Bundle", isDirectory: true)
        try fs.createDirectory(at: bundleRoot) // empty bundle -> no strings resolve

        let asset = AerialAsset(
            id: "64D11DAB-3B57-4F14-AD2F-E59A9282FA44",
            categories: [],
            localizedNameKey: "MISSING_NAME",
            shotID: "MISSING_SHOT",
            accessibilityLabel: "Tahoe Day",
            urlVariants: [:]
        )

        let resolver = CategoryResolver(fileSystem: fs, bundleRootURL: bundleRoot)
        let name = await resolver.assetName(for: asset)
        #expect(name == "Tahoe Day")
    }

    @Test func testAssetNames_bulkAppliesFullFallbackChain() async throws {
        let fs = InMemoryFileSystem()
        let bundleRoot = URL(fileURLWithPath: "/Bundle", isDirectory: true)
        let en = bundleRoot.appendingPathComponent("en.lproj", isDirectory: true)
        try fs.createDirectory(at: bundleRoot)
        try fs.createDirectory(at: en)

        try fs.writeData(
            stringsPlistXML(["NameKeyA": "Via NameKey", "SHOT_B_NAME": "Via ShotID"]),
            to: en.appendingPathComponent("Localizable.strings"),
            options: [.atomic]
        )

        let assets = [
            AerialAsset(id: "a", categories: [], localizedNameKey: "NameKeyA", urlVariants: [:]),
            AerialAsset(id: "b", categories: [], shotID: "SHOT_B", urlVariants: [:]),
            AerialAsset(id: "c", categories: [], accessibilityLabel: "Via Label", urlVariants: [:]),
            AerialAsset(id: "d", categories: [], urlVariants: [:]),
        ]

        let resolver = CategoryResolver(fileSystem: fs, bundleRootURL: bundleRoot)
        let names = await resolver.assetNames(for: assets)

        #expect(names["a"] == "Via NameKey")
        #expect(names["b"] == "Via ShotID")
        #expect(names["c"] == "Via Label")
        #expect(names["d"] == "d") // last-resort: the ID itself
    }

    @Test func testResolveExcludedCategoryIDs_commaSplittingAndSubstringMatch() async throws {
        let fs = InMemoryFileSystem()
        let bundleRoot = URL(fileURLWithPath: "/Bundle", isDirectory: true)
        let en = bundleRoot.appendingPathComponent("en.lproj", isDirectory: true)
        try fs.createDirectory(at: bundleRoot)
        try fs.createDirectory(at: en)

        let stringsURL = en.appendingPathComponent("Localizable.strings")
        try fs.writeData(stringsPlistXML(["EarthKey": "Earth", "UnderwaterKey": "Underwater"]), to: stringsURL, options: [.atomic])

        let categories = [
            AerialCategory(id: "earth-id", localizedNameKey: "EarthKey"),
            AerialCategory(id: "underwater-id", localizedNameKey: "UnderwaterKey"),
        ]

        let resolver = CategoryResolver(fileSystem: fs, bundleRootURL: bundleRoot)
        let result = await resolver.resolveExcludedCategoryIDs(excludeTerms: ["Earth, Under"], categories: categories)

        #expect(result.excludedIDs.contains("earth-id"))
        #expect(result.excludedIDs.contains("underwater-id"))
    }

    @Test func testAssetName_prefersNameKey() async throws {
        let fs = InMemoryFileSystem()
        let bundleRoot = URL(fileURLWithPath: "/Bundle", isDirectory: true)
        let en = bundleRoot.appendingPathComponent("en.lproj", isDirectory: true)
        try fs.createDirectory(at: bundleRoot)
        try fs.createDirectory(at: en)

        let stringsURL = en.appendingPathComponent("Localizable.strings")
        try fs.writeData(stringsPlistXML(["A001_C001_120530_NAME": "North Atlantic"]), to: stringsURL, options: [.atomic])

        let resolver = CategoryResolver(fileSystem: fs, bundleRootURL: bundleRoot)
        let name = await resolver.assetName(for: "A001_C001_120530")
        #expect(name == "North Atlantic")
    }

    @Test func testAssetName_usesAssetLocalizedNameKeyForGuidIDs() async throws {
        let fs = InMemoryFileSystem()
        let bundleRoot = URL(fileURLWithPath: "/Bundle", isDirectory: true)
        let en = bundleRoot.appendingPathComponent("en.lproj", isDirectory: true)
        try fs.createDirectory(at: bundleRoot)
        try fs.createDirectory(at: en)

        let stringsURL = en.appendingPathComponent("Localizable.strings")
        try fs.writeData(stringsPlistXML(["A001_C001_120530_NAME": "North Atlantic"]), to: stringsURL, options: [.atomic])

        let asset = AerialAsset(
            id: "64D11DAB-3B57-4F14-AD2F-E59A9282FA44",
            categories: [],
            localizedNameKey: "A001_C001_120530_NAME",
            shotID: "A001_C001_120530",
            urlVariants: [:]
        )

        let resolver = CategoryResolver(fileSystem: fs, bundleRootURL: bundleRoot)
        let name = await resolver.assetName(for: asset)
        #expect(name == "North Atlantic")
    }

    @Test func testAssetName_fallsBackToDirectKey() async throws {
        let fs = InMemoryFileSystem()
        let bundleRoot = URL(fileURLWithPath: "/Bundle", isDirectory: true)
        let en = bundleRoot.appendingPathComponent("en.lproj", isDirectory: true)
        try fs.createDirectory(at: bundleRoot)
        try fs.createDirectory(at: en)

        let stringsURL = en.appendingPathComponent("Localizable.strings")
        try fs.writeData(stringsPlistXML(["A001_C001_120530": "Direct Value"]), to: stringsURL, options: [.atomic])

        let resolver = CategoryResolver(fileSystem: fs, bundleRootURL: bundleRoot)
        let name = await resolver.assetName(for: "A001_C001_120530")
        #expect(name == "Direct Value")
    }

    @Test func testCategoryIDToNames_doesNotIncludeSubcategories() async throws {
        let fs = InMemoryFileSystem()
        let bundleRoot = URL(fileURLWithPath: "/Bundle", isDirectory: true)
        let en = bundleRoot.appendingPathComponent("en.lproj", isDirectory: true)
        try fs.createDirectory(at: bundleRoot)
        try fs.createDirectory(at: en)

        let stringsURL = en.appendingPathComponent("Localizable.strings")
        try fs.writeData(stringsPlistXML(["TopKey": "Top", "SubKey": "Sub"]), to: stringsURL, options: [.atomic])

        let categories = [
            AerialCategory(
                id: "top-id",
                localizedNameKey: "TopKey",
                subcategories: [
                    AerialCategory(id: "sub-id", localizedNameKey: "SubKey"),
                ]
            )
        ]

        let resolver = CategoryResolver(fileSystem: fs, bundleRootURL: bundleRoot)
        let map = await resolver.categoryIDToNames(categories: categories)

        #expect(map["top-id"]?.contains("Top") == true)
        #expect(map["sub-id"] == nil)
    }

    @Test func testResolveExcludedCategoryIDs_matchesByExactID() async throws {
        let fs = InMemoryFileSystem()
        let bundleRoot = URL(fileURLWithPath: "/Bundle", isDirectory: true)
        try fs.createDirectory(at: bundleRoot)

        let categories = [
            AerialCategory(id: "earth-id", localizedNameKey: nil),
            AerialCategory(id: "underwater-id", localizedNameKey: nil),
        ]

        let resolver = CategoryResolver(fileSystem: fs, bundleRootURL: bundleRoot)
        let result = await resolver.resolveExcludedCategoryIDs(excludeTerms: ["underwater-id"], categories: categories)

        #expect(result.excludedIDs == ["underwater-id"])
    }

    @Test func testCaching_returnsCachedResultOnSubsequentCalls() async throws {
        let fs = InMemoryFileSystem()
        let bundleRoot = URL(fileURLWithPath: "/Bundle", isDirectory: true)
        let en = bundleRoot.appendingPathComponent("en.lproj", isDirectory: true)
        try fs.createDirectory(at: bundleRoot)
        try fs.createDirectory(at: en)

        let stringsURL = en.appendingPathComponent("Localizable.strings")
        try fs.writeData(stringsPlistXML(["TestKey": "TestValue"]), to: stringsURL, options: [.atomic])

        let resolver = CategoryResolver(fileSystem: fs, bundleRootURL: bundleRoot)

        // First call should load from file system
        let first = await resolver.loadAllLocalizedStrings()
        #expect(first["TestKey"]?.contains("TestValue") == true)

        // Modify the file on disk (simulate change)
        try fs.writeData(stringsPlistXML(["TestKey": "ModifiedValue"]), to: stringsURL, options: [.atomic])

        // Second call should return cached result (not the modified value)
        let second = await resolver.loadAllLocalizedStrings()
        #expect(second["TestKey"]?.contains("TestValue") == true)
    }

    @Test func testInvalidateCache_forcesReload() async throws {
        let fs = InMemoryFileSystem()
        let bundleRoot = URL(fileURLWithPath: "/Bundle", isDirectory: true)
        let en = bundleRoot.appendingPathComponent("en.lproj", isDirectory: true)
        try fs.createDirectory(at: bundleRoot)
        try fs.createDirectory(at: en)

        let stringsURL = en.appendingPathComponent("Localizable.strings")
        try fs.writeData(stringsPlistXML(["TestKey": "TestValue"]), to: stringsURL, options: [.atomic])

        let resolver = CategoryResolver(fileSystem: fs, bundleRootURL: bundleRoot)

        // First call
        let first = await resolver.loadAllLocalizedStrings()
        #expect(first["TestKey"]?.contains("TestValue") == true)

        // Modify file and invalidate cache
        try fs.writeData(stringsPlistXML(["TestKey": "ModifiedValue"]), to: stringsURL, options: [.atomic])
        await resolver.invalidateCache()

        // After invalidation, should load fresh data
        let second = await resolver.loadAllLocalizedStrings()
        #expect(second["TestKey"]?.contains("ModifiedValue") == true)
    }

    @Test func testDefaultInit_prefersWallpaperManifestStringsBundle() async throws {
        let fs = InMemoryFileSystem()
        let home = URL(fileURLWithPath: "/home", isDirectory: true)

        let preferredRoot = AerialSystemPaths.preferredStringsBundleRootURL(homeDirectoryURL: home)
        let legacyRoot = AerialSystemPaths.legacyStringsBundleRootURL()

        let preferredEn = preferredRoot.appendingPathComponent("en.lproj", isDirectory: true)
        let legacyEn = legacyRoot.appendingPathComponent("en.lproj", isDirectory: true)

        try fs.createDirectory(at: preferredRoot)
        try fs.createDirectory(at: preferredEn)
        try fs.createDirectory(at: legacyRoot)
        try fs.createDirectory(at: legacyEn)

        try fs.writeData(
            stringsPlistXML(["TestKey": "PreferredValue"]),
            to: preferredEn.appendingPathComponent("Localizable.strings"),
            options: [.atomic]
        )
        try fs.writeData(
            stringsPlistXML(["TestKey": "LegacyValue"]),
            to: legacyEn.appendingPathComponent("Localizable.strings"),
            options: [.atomic]
        )

        let resolver = CategoryResolver(fileSystem: fs, homeDirectoryURL: home)
        let strings = await resolver.loadAllLocalizedStrings()
        #expect(strings["TestKey"]?.contains("PreferredValue") == true)
    }

    @Test func testDefaultInit_fallsBackToLegacyStringsBundleWhenPreferredMissing() async throws {
        let fs = InMemoryFileSystem()
        let home = URL(fileURLWithPath: "/home", isDirectory: true)

        let legacyRoot = AerialSystemPaths.legacyStringsBundleRootURL()
        let legacyEn = legacyRoot.appendingPathComponent("en.lproj", isDirectory: true)

        try fs.createDirectory(at: legacyRoot)
        try fs.createDirectory(at: legacyEn)
        try fs.writeData(
            stringsPlistXML(["TestKey": "LegacyValue"]),
            to: legacyEn.appendingPathComponent("Localizable.strings"),
            options: [.atomic]
        )

        let resolver = CategoryResolver(fileSystem: fs, homeDirectoryURL: home)
        let strings = await resolver.loadAllLocalizedStrings()
        #expect(strings["TestKey"]?.contains("LegacyValue") == true)
    }
}
